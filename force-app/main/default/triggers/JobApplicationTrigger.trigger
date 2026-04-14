/**
 * @description Trigger on Job_Application__c to prevent a candidate from having
 *              more than one active application for the same job position.
 *              A candidate is allowed to reapply if their previous application
 *              was Rejected or Withdrawn.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
trigger JobApplicationTrigger on Job_Application__c (before insert) {

    Set<Id> candidateIds = new Set<Id>();
    Set<Id> positionIds = new Set<Id>();

    for (Job_Application__c app : Trigger.new) {
        candidateIds.add(app.Candidate__c);
        positionIds.add(app.Job_Position__c);
    }

    List<Job_Application__c> existing = [
        SELECT Id, Candidate__c, Job_Position__c
        FROM Job_Application__c
        WHERE Candidate__c IN :candidateIds
        AND Job_Position__c IN :positionIds
        AND Stage__c NOT IN ('Rejected', 'Withdrawn')
    ];

    Map<String, Boolean> existingMap = new Map<String, Boolean>();
    for (Job_Application__c app : existing) {
        String key = app.Candidate__c + '_' + app.Job_Position__c;
        existingMap.put(key, true);
    }

    for (Job_Application__c app : Trigger.new) {
        String key = app.Candidate__c + '_' + app.Job_Position__c;
        if (existingMap.containsKey(key)) {
            app.addError('You already have an active application for this position.');
        }
    }
}