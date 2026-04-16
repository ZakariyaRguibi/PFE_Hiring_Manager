/**
 * Handler for InterviewStageTrigger.
 * Enforces that Stage_Number__c is unique within the same Job_Position__c.
 * Salesforce field-level unique=true is too restrictive (global uniqueness),
 * so scoped uniqueness is enforced here via SOQL instead.
 */
public inherited sharing class InterviewStageTriggerHandler {
  /**
   * Entry point called by the trigger on before insert and before update.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  public static void handle(
    List<Interview_Stage__c> newList,
    Map<Id, Interview_Stage__c> oldMap
  ) {
    validateUniqueStageNumberPerPosition(newList, oldMap);
  }

  /**
   * Stage_Number__c must be unique within the same Job_Position__c.
   * Salesforce field-level unique=true enforces global uniqueness, which is
   * too restrictive — stage numbers (1, 2, 3…) are naturally reused across
   * different positions. This method enforces scoped uniqueness instead.
   *
   * Records being updated are excluded from the SOQL so that swapping stage
   * numbers between records in the same transaction is correctly allowed —
   * duplicates within the transaction are detected via the in-memory batchKeys set.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  private static void validateUniqueStageNumberPerPosition(
    List<Interview_Stage__c> newList,
    Map<Id, Interview_Stage__c> oldMap
  ) {
    List<Interview_Stage__c> toCheck = collectChangedStages(newList, oldMap);
    if (toCheck.isEmpty()) {
      return;
    }

    Set<String> existingKeys = queryExistingKeys(toCheck);
    Set<String> batchKeys = new Set<String>();

    for (Interview_Stage__c stage : toCheck) {
      String key = stage.Job_Position__c + '_' + stage.Stage_Number__c;
      if (existingKeys.contains(key) || batchKeys.contains(key)) {
        stage.Stage_Number__c.addError(
          'Stage Number ' +
            String.valueOf(stage.Stage_Number__c.intValue()) +
            ' already exists for this Job Position.'
        );
      } else {
        batchKeys.add(key);
      }
    }
  }

  /**
   * Filters out records where neither Stage_Number__c nor Job_Position__c changed,
   * avoiding unnecessary SOQL on unrelated updates.
   * @param newList incoming records
   * @param oldMap previous state map (null on insert)
   * @return records that require a uniqueness check
   */
  private static List<Interview_Stage__c> collectChangedStages(
    List<Interview_Stage__c> newList,
    Map<Id, Interview_Stage__c> oldMap
  ) {
    List<Interview_Stage__c> toCheck = new List<Interview_Stage__c>();
    for (Interview_Stage__c stage : newList) {
      if (stage.Job_Position__c == null || stage.Stage_Number__c == null) {
        continue;
      }
      if (oldMap != null) {
        Interview_Stage__c old = oldMap.get(stage.Id);
        if (
          old.Stage_Number__c == stage.Stage_Number__c &&
          old.Job_Position__c == stage.Job_Position__c
        ) {
          continue;
        }
      }
      toCheck.add(stage);
    }
    return toCheck;
  }

  /**
   * Queries existing Interview_Stage__c records for the affected positions,
   * excluding the records currently being updated so that stage number swaps
   * within a single transaction are not incorrectly flagged as duplicates.
   * WITH SYSTEM_MODE bypasses FLS and sharing rules so the uniqueness check
   * runs consistently regardless of the running user's field permissions.
   * @param toCheck records to check
   * @return set of existing composite keys (positionId + '_' + stageNumber)
   */
  private static Set<String> queryExistingKeys(
    List<Interview_Stage__c> toCheck
  ) {
    Set<Id> positionIds = new Set<Id>();
    Set<Id> toCheckIds = new Set<Id>();
    for (Interview_Stage__c stage : toCheck) {
      positionIds.add(stage.Job_Position__c);
      if (stage.Id != null) {
        toCheckIds.add(stage.Id);
      }
    }
    Set<String> keys = new Set<String>();
    for (Interview_Stage__c ex : [
      SELECT Id, Job_Position__c, Stage_Number__c
      FROM Interview_Stage__c
      WHERE Job_Position__c IN :positionIds AND Id NOT IN :toCheckIds
      WITH SYSTEM_MODE
    ]) {
      keys.add(ex.Job_Position__c + '_' + ex.Stage_Number__c);
    }
    return keys;
  }
}
