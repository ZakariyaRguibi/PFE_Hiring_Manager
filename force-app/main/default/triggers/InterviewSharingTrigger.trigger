/**
 * @description Trigger for Interview__c object.
 *              Delegates all logic to InterviewSharingHandler.
 *
 * @author      Hiba Balhirch
 * @version     1.2
 */
trigger InterviewSharingTrigger on Interview__c(
  after insert,
  after update,
  after delete
) {
  InterviewSharingHandler handler = new InterviewSharingHandler();

  if (Trigger.isAfter && Trigger.isInsert) {
    handler.onAfterInsert(Trigger.new);
  }

  if (Trigger.isAfter && Trigger.isUpdate) {
    handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
  }

  if (Trigger.isAfter && Trigger.isDelete) {
    handler.onAfterDelete(Trigger.old);
  }
}
