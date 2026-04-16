/**
 * @description Trigger on Candidate__c to prevent duplicate candidate records.
 *              Delegates all logic to CandidateTriggerHandler.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
trigger CandidateTrigger on Candidate__c(before insert) {
  CandidateTriggerHandler handler = new CandidateTriggerHandler();
  if (Trigger.isBefore && Trigger.isInsert) {
    handler.onBeforeInsert(Trigger.new);
  }
}
