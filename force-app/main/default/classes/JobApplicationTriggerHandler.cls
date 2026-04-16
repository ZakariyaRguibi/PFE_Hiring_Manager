/**
 * @description Handler class for JobApplicationTrigger.
 *              Prevents a candidate from having more than one active
 *              application for the same job position.
 *              A candidate is allowed to reapply if their previous
 *              application was Rejected or Withdrawn.
 *
 *              Runs with sharing because:
 *              - Candidates can only see their own applications (Private OWD)
 *              - WITH USER_MODE is safe here — we only need to check
 *                the running candidate's own applications, not all candidates
 *
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
public with sharing class JobApplicationTriggerHandler {
  /**
   * @description Handles before insert event.
   *              Checks for existing active applications for the
   *              same candidate and job position combination.
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

    List<Job_Application__c> existing = [
      SELECT Id, Candidate__c, Job_Position__c
      FROM Job_Application__c
      WHERE
        Candidate__c IN :candidateIds
        AND Job_Position__c IN :positionIds
        AND Stage__c NOT IN ('Rejected', 'Withdrawn')
      WITH USER_MODE
    ];

    Map<String, Boolean> existingMap = new Map<String, Boolean>();
    for (Job_Application__c app : existing) {
      String key = app.Candidate__c + '_' + app.Job_Position__c;
      existingMap.put(key, true);
    }

    for (Job_Application__c app : newApplications) {
      String key = app.Candidate__c + '_' + app.Job_Position__c;
      if (existingMap.containsKey(key)) {
        app.addError(
          'You already have an active application for this position.'
        );
      }
    }
  }
}
