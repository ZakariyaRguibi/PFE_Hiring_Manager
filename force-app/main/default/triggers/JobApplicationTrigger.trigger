/**
 * @description Trigger on Job_Application__c to prevent duplicate applications.
 *              Delegates all logic to JobApplicationTriggerHandler.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
trigger JobApplicationTrigger on Job_Application__c(before insert) {
    new JobApplicationTriggerHandler().onBeforeInsert(Trigger.new);
}