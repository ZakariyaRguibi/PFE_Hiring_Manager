/**
 * @description Handler class for JobApplicationTrigger.
 *              Prevents a candidate from having more than one
 *              application for the same job position.
 *              Reapplication is not allowed, even if the previous
 *              application was rejected.
 *
 *              Runs with sharing because candidates should only be
 *              evaluated against records they are allowed to access
 *              in this trigger context.
 *
 * @author Hiba Balhirch
 * @date 2026-04-16
 */
public with sharing class JobApplicationTriggerHandler {
  /**
   * @description Handles before insert event.
   *              Blocks insertion if an application already exists
   *              for the same Candidate__c + Job_Position__c pair.
   *              Also blocks duplicate pairs inside the same insert batch.
   * @param newApplications List of new Job_Application__c records being inserted
   */
  public void onBeforeInsert(List<Job_Application__c> newApplications) {
    Set<Id> candidateIds = new Set<Id>();
    Set<Id> positionIds = new Set<Id>();

    for (Job_Application__c app : newApplications) {
      if (app.Candidate__c != null) {
        candidateIds.add(app.Candidate__c);
      }
      if (app.Job_Position__c != null) {
        positionIds.add(app.Job_Position__c);
      }
    }

    if (candidateIds.isEmpty() || positionIds.isEmpty()) {
      return;
    }

    List<Job_Application__c> existingApplications = [
      SELECT Id, Candidate__c, Job_Position__c
      FROM Job_Application__c
      WHERE Candidate__c IN :candidateIds AND Job_Position__c IN :positionIds
      WITH USER_MODE
    ];

    Set<String> existingKeys = new Set<String>();
    for (Job_Application__c app : existingApplications) {
      existingKeys.add(buildKey(app.Candidate__c, app.Job_Position__c));
    }

    Set<String> batchKeys = new Set<String>();
    for (Job_Application__c app : newApplications) {
      if (app.Candidate__c == null || app.Job_Position__c == null) {
        continue;
      }

      String key = buildKey(app.Candidate__c, app.Job_Position__c);

      if (existingKeys.contains(key) || batchKeys.contains(key)) {
        app.addError(
          'A candidate can apply only once for the same job position.'
        );
      } else {
        batchKeys.add(key);
      }
    }
  }

  /**
   * @description Builds a unique composite key for candidate-position pair.
   * @param candidateId Candidate Id
   * @param positionId Job Position Id
   * @return String composite key
   */
  private static String buildKey(Id candidateId, Id positionId) {
    return String.valueOf(candidateId) + '_' + String.valueOf(positionId);
  }
}
