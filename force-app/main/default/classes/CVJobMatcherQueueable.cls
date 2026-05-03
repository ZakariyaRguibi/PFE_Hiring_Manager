/**
 * @description Asynchronous job that invokes the CV_Job_Matcher Einstein Prompt
 *              Template to compute a relevance score for a Job_Application__c.
 *
 *              Runs after the application is inserted (enqueued by
 *              JobApplicationTriggerHandler). Calls the CV_Job_Matcher prompt
 *              template passing the Application and its related Job Position,
 *              parses the JSON response, and writes all sub-scores, the weighted
 *              AI_Score__c, and the hard-filter decision back to the record.
 *
 *              If scoring fails for any reason the application is left untouched
 *              so it can be reviewed manually — it is never blocked or deleted.
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
public with sharing class CVJobMatcherQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static final String PROMPT_TEMPLATE_NAME = 'CV_Job_Matcher';

  /** @description Id of the Job_Application__c record to score. */
  private final Id applicationId;

  /**
   * @description Constructor.
   * @param applicationId Id of the Job_Application__c to score
   */
  public CVJobMatcherQueueable(Id applicationId) {
    this.applicationId = applicationId;
  }

  /**
   * @description Queueable entry point. Invokes Einstein and updates the application.
   * @param ctx Queueable context provided by the platform
   */
  public void execute(QueueableContext ctx) {
    try {
      Job_Application__c app = fetchApplication(applicationId);
      if (app == null) {
        return;
      }

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = invokePromptTemplate(
        app
      );

      String rawJson = response.generations[0].text.trim();
      Job_Application__c scored = buildUpdate(applicationId, rawJson);
      update as system scored;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'CVJobMatcherQueueable failed for application ' +
          applicationId +
          ': ' +
          e.getMessage()
      );
    }
  }

  /**
   * @description Fetches the application with its related position fields needed by the prompt.
   * @param appId Id of the application to fetch
   * @return      Populated Job_Application__c, or null if not found
   */
  @TestVisible
  private static Job_Application__c fetchApplication(Id appId) {
    List<Job_Application__c> apps = [
      SELECT
        Id,
        Extracted_Skills__c,
        Extracted_Keywords__c,
        Extracted_Education__c,
        Extracted_Experience__c,
        Job_Position__c
      FROM Job_Application__c
      WHERE Id = :appId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return apps.isEmpty() ? null : apps[0];
  }

  /**
   * @description Invokes the CV_Job_Matcher Einstein Prompt Template.
   * @param app The application record to pass as input
   * @return    Raw Einstein response
   */
  @TestVisible
  private static ConnectApi.EinsteinPromptTemplateGenerationsRepresentation invokePromptTemplate(
    Job_Application__c app
  ) {
    ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();

    ConnectApi.WrappedValue appValue = new ConnectApi.WrappedValue();
    appValue.value = app.Id;

    ConnectApi.WrappedValue posValue = new ConnectApi.WrappedValue();
    posValue.value = app.Job_Position__c;

    input.inputParams = new Map<String, ConnectApi.WrappedValue>{
      'Input:Application' => appValue,
      'Input:Position' => posValue
    };

    return ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
      PROMPT_TEMPLATE_NAME,
      input
    );
  }

  /**
   * @description Parses the Einstein JSON response and builds the update record.
   * @param appId   Id of the application to update
   * @param rawJson JSON string from the LLM response
   * @return        Job_Application__c with scored fields populated
   */
  @TestVisible
  static Job_Application__c buildUpdate(Id appId, String rawJson) {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawJson);

    Decimal skillsScore = toDecimal(parsed.get('Skills_Match_Score'));
    Decimal educationScore = toDecimal(parsed.get('Education_Score'));
    Decimal experienceScore = toDecimal(parsed.get('Experience_Score'));
    Decimal keywordsScore = toDecimal(parsed.get('Keywords_Score'));
    Decimal finalScore = toDecimal(parsed.get('Final_Score'));

    // Clamp AI_Score to [0, 100]
    Decimal aiScore = finalScore != null
      ? Math.max(0, Math.min(100, finalScore))
      : null;

    Job_Application__c scored = new Job_Application__c(Id = appId);
    scored.Skills_Match_Score__c = skillsScore;
    scored.Education_Score__c = educationScore;
    scored.Experience_Score__c = experienceScore;
    scored.Keywords_Score__c = keywordsScore;
    scored.AI_Score__c = aiScore;
    scored.AI_Scored_At__c = Datetime.now();
    scored.Passed_Hard_Filter__c = parsed.get('Passed_Hard_Filter') == true;
    scored.AI_Filter_Decision__c = (String) parsed.get('AI_Filter_Decision');
    scored.Filter_Rejection_Reason__c = (String) parsed.get('Filter_Rejection_Reason');
    return scored;
  }

  /**
   * @description Safely converts an Object from JSON deserialization to Decimal.
   *              Returns null if the value is null or not numeric.
   * @param val Value from JSON.deserializeUntyped()
   * @return    Decimal value, or null
   */
  @TestVisible
  private static Decimal toDecimal(Object val) {
    if (val == null) {
      return null;
    }
    try {
      return Decimal.valueOf(String.valueOf(val));
    } catch (Exception e) {
      return null;
    }
  }
}
