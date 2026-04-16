/**
 * @description Trigger on Job_Application__c to prevent a candidate from having
 *              more than one active application for the same job position.
 *              Delegates all logic to JobApplicationTriggerHandler.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
trigger JobApplicationTrigger on Job_Application__c(before insert) {
  JobApplicationTriggerHandler handler = new JobApplicationTriggerHandler();
  if (Trigger.isBefore && Trigger.isInsert) {
    handler.onBeforeInsert(Trigger.new);
  }
}
