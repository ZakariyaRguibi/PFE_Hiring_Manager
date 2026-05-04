/**
 * @description Service class for parsing candidate CVs using Einstein Prompt Builder.
 *              Called directly from the portal LWC when a candidate uploads their CV,
 *              before the Job_Application__c record is created.
 *
 *              The CV_Parser prompt template takes a ContentDocument as input and
 *              returns a JSON object with extracted skills, keywords, education, and
 *              years of experience.
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
public with sharing class CVParserService {
  @TestVisible
  private static final String PROMPT_TEMPLATE_NAME = 'CV_Parser';

  @TestVisible
  private static final String PARSER_VERSION = '1.0';

  /**
   * @description Parses a CV file and returns extracted structured data.
   *              Called by the portal LWC after the candidate uploads their CV.
   *
   * @param contentDocumentId  Id of the ContentDocument (uploaded CV file)
   * @return                   CVParseResult with extracted fields, or error details
   */
  @AuraEnabled
  public static CVParseResult parseCV(Id contentDocumentId) {
    if (contentDocumentId == null) {
      throw new AuraHandledException('contentDocumentId is required.');
    }

    try {
      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = invokePromptTemplate(
        contentDocumentId
      );

      String rawJson = response.generations[0].text.trim();
      return parseResponse(rawJson);
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException('CV parsing failed: ' + e.getMessage());
    }
  }

  /**
   * @description Invokes the CV_Parser Einstein Prompt Template.
   *
   * @param contentDocumentId  Id of the ContentDocument to pass as input
   * @return                   Raw response from Einstein LLM
   */
  @TestVisible
  private static ConnectApi.EinsteinPromptTemplateGenerationsRepresentation invokePromptTemplate(
    Id contentDocumentId
  ) {
    ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();

    ConnectApi.WrappedValue cvValue = new ConnectApi.WrappedValue();
    cvValue.value = contentDocumentId;

    input.inputParams = new Map<String, ConnectApi.WrappedValue>{
      'Input:CV' => cvValue
    };

    return ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
      PROMPT_TEMPLATE_NAME,
      input
    );
  }

  /**
   * @description Parses the raw JSON string returned by Einstein into a CVParseResult.
   *
   * @param rawJson  JSON string from the LLM response
   * @return         Populated CVParseResult
   */
  @TestVisible
  private static CVParseResult parseResponse(String rawJson) {
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      rawJson
    );

    CVParseResult result = new CVParseResult();
    result.extractedSkills = (String) parsed.get('Extracted_Skills');
    result.extractedKeywords = (String) parsed.get('Extracted_Keywords');
    result.extractedEducation = (String) parsed.get('Extracted_Education');
    result.extractedExperience = parsed.get('Extracted_Experience') != null
      ? Integer.valueOf(parsed.get('Extracted_Experience'))
      : null;
    result.parserVersion = PARSER_VERSION;
    result.parsedAt = Datetime.now();
    result.success = true;
    return result;
  }

  /**
   * @description Data transfer object returned to the portal LWC.
   */
  public class CVParseResult {
    /** @description Comma-separated list of technical and soft skills extracted from the CV. */
    @AuraEnabled
    public String extractedSkills { get; set; }
    /** @description Comma-separated list of keywords relevant for job matching. */
    @AuraEnabled
    public String extractedKeywords { get; set; }
    /** @description Highest education level: High School, Bachelor, Master, PhD, or Other. */
    @AuraEnabled
    public String extractedEducation { get; set; }
    /** @description Number of years of professional experience. */
    @AuraEnabled
    public Integer extractedExperience { get; set; }
    /** @description Version of the parser engine used (e.g. 1.0). */
    @AuraEnabled
    public String parserVersion { get; set; }
    /** @description Timestamp when parsing completed. */
    @AuraEnabled
    public Datetime parsedAt { get; set; }
    /** @description True if parsing succeeded, false if it failed. */
    @AuraEnabled
    public Boolean success { get; set; }
  }
}
