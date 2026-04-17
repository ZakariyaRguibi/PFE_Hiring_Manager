/**
 * @description Handles validation logic for Interview__c triggers.
 * Enforces score limits and prevents duplicate scheduled datetimes per candidate.
 */
public inherited sharing class InterviewTriggerHandler {
  /**
   * @description Entry point called by the trigger. Runs all validations.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  public static void handle(
    List<Interview__c> newList,
    Map<Id, Interview__c> oldMap
  ) {
    validateScoreAgainstMaxScore(newList);
    validateNoDuplicateDateTime(newList, oldMap);
  }

  /**
   * @description Score__c must be <= parent Interview_Stage__c.Max_Score__c.
   * @param newList records being inserted or updated
   */
  private static void validateScoreAgainstMaxScore(List<Interview__c> newList) {
    Set<Id> stageIds = new Set<Id>();
    for (Interview__c interview : newList) {
      if (interview.Interview_Stage__c != null && interview.Score__c != null) {
        stageIds.add(interview.Interview_Stage__c);
      }
    }
    if (stageIds.isEmpty()) {
      return;
    }

    Map<Id, Interview_Stage__c> stagesMap = new Map<Id, Interview_Stage__c>(
      [
        SELECT Id, Max_Score__c
        FROM Interview_Stage__c
        WHERE Id IN :stageIds
        WITH SYSTEM_MODE
      ]
    );

    for (Interview__c interview : newList) {
      if (interview.Interview_Stage__c != null && interview.Score__c != null) {
        checkScoreAgainstStage(
          interview,
          stagesMap.get(interview.Interview_Stage__c)
        );
      }
    }
  }

  /**
   * @description Adds a field error if the interview score exceeds the stage max.
   * @param interview the interview record being validated
   * @param stage the parent Interview_Stage__c record
   */
  private static void checkScoreAgainstStage(
    Interview__c interview,
    Interview_Stage__c stage
  ) {
    if (stage == null || stage.Max_Score__c == null) {
      return;
    }
    if (interview.Score__c > stage.Max_Score__c) {
      interview.Score__c.addError(
        'Score (' +
          interview.Score__c +
          ') cannot exceed the stage\'s Max Score (' +
          stage.Max_Score__c +
          ').'
      );
    }
  }

  /**
   * @description Filters interviews where Scheduled_DateTime__c or Job_Application__c changed.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   * @return list of interviews that require duplicate datetime checking
   */
  private static List<Interview__c> collectChangedForDateCheck(
    List<Interview__c> newList,
    Map<Id, Interview__c> oldMap
  ) {
    List<Interview__c> toCheck = new List<Interview__c>();
    for (Interview__c interview : newList) {
      if (
        interview.Job_Application__c == null ||
        interview.Scheduled_DateTime__c == null
      ) {
        continue;
      }
      if (oldMap != null) {
        Interview__c old = oldMap.get(interview.Id);
        if (
          old.Scheduled_DateTime__c == interview.Scheduled_DateTime__c &&
          old.Job_Application__c == interview.Job_Application__c
        ) {
          continue;
        }
      }
      toCheck.add(interview);
    }
    return toCheck;
  }

  /**
   * @description A candidate (via Job_Application__c) cannot have two interviews at the same Scheduled_DateTime__c.
   * Cancelled and No Show interviews are excluded from the check.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  private static void validateNoDuplicateDateTime(
    List<Interview__c> newList,
    Map<Id, Interview__c> oldMap
  ) {
    List<Interview__c> toCheck = collectChangedForDateCheck(newList, oldMap);
    if (toCheck.isEmpty()) {
      return;
    }

    Set<Id> appIds = new Set<Id>();
    Set<Datetime> dateTimes = new Set<Datetime>();
    for (Interview__c interview : toCheck) {
      appIds.add(interview.Job_Application__c);
      dateTimes.add(interview.Scheduled_DateTime__c);
    }

    List<Interview__c> existing = [
      SELECT Id, Job_Application__c, Scheduled_DateTime__c
      FROM Interview__c
      WHERE
        Job_Application__c IN :appIds
        AND Scheduled_DateTime__c IN :dateTimes
        AND Status__c NOT IN ('Cancelled', 'No_Show')
      WITH SYSTEM_MODE
    ];

    Map<String, Id> existingKeyToId = new Map<String, Id>();
    for (Interview__c ex : existing) {
      existingKeyToId.put(
        ex.Job_Application__c + '_' + ex.Scheduled_DateTime__c,
        ex.Id
      );
    }

    Set<String> batchKeys = new Set<String>();
    for (Interview__c interview : toCheck) {
      String key =
        interview.Job_Application__c +
        '_' +
        interview.Scheduled_DateTime__c;
      if (batchKeys.contains(key)) {
        interview.Scheduled_DateTime__c.addError(
          'This candidate already has an interview scheduled at this date and time.'
        );
        continue;
      }
      batchKeys.add(key);
      if (existingKeyToId.containsKey(key)) {
        Id conflictId = existingKeyToId.get(key);
        if (conflictId != interview.Id) {
          interview.Scheduled_DateTime__c.addError(
            'This candidate already has an interview scheduled at this date and time.'
          );
        }
      }
    }
  }
}
