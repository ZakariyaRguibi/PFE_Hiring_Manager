/**
 * @description Handler class for JobApplicationTrigger.
 *
 *              Before insert: prevents a candidate from having more than one
 *              active application for the same job position. A candidate may
 *              reapply only if their previous application was Rejected or Withdrawn.
 *
 *              After insert: enqueues CVJobMatcherQueueable for each new
 *              application so the relevance score is computed asynchronously
 *              without blocking the candidate's submission transaction.
 *
 * @author Marwane Romani
 * @author Hiba Balhirch
 * @date 2026-04-30
 */
public with sharing class JobApplicationTriggerHandler {
  /**
   * @description Entry point called by JobApplicationTrigger.
   * @param newList       Trigger.new
   * @param oldMap        Trigger.oldMap
   * @param operationType Trigger.operationType
   */
  public static void handle(
    List<Job_Application__c> newList,
    Map<Id, Job_Application__c> oldMap,
    System.TriggerOperation operationType
  ) {
    if (operationType == System.TriggerOperation.BEFORE_INSERT) {
      preventDuplicateApplication(newList);
    } else if (operationType == System.TriggerOperation.AFTER_INSERT) {
      enqueueScoring(newList);
    }
  }

  /**
   * @description Blocks insertion if the candidate already has an active
   *              application for the same position.
   * @param newApplications List of incoming Job_Application__c records
   * @author Hiba Balhirch
   */
  private static void preventDuplicateApplication(
    List<Job_Application__c> newApplications
  ) {
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
      existingMap.put(app.Candidate__c + '_' + app.Job_Position__c, true);
    }

    for (Job_Application__c app : newApplications) {
      if (
        existingMap.containsKey(app.Candidate__c + '_' + app.Job_Position__c)
      ) {
        app.addError(
          'You already have an active application for this position.'
        );
      }
    }
  }

  /**
   * @description Collects application Ids that have a position, then enqueues
   *              one CVJobMatcherQueueable per Id outside any loop to respect
   *              governor limits.
   * @param newApplications List of newly inserted Job_Application__c records
   * @author Marwane Romani
   */
  private static void enqueueScoring(List<Job_Application__c> newApplications) {
    for (Job_Application__c app : newApplications) {
      if (app.Job_Position__c != null) {
        System.enqueueJob(new CVJobMatcherQueueable(app.Id));
        return;
      }
    }
  }
}
