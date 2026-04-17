/**
 * @description Trigger for Interview__c object.
 *              Delegates all logic to InterviewSharingHandler.
 *
 * @author      Hiba Balhirch
 * @version     1.1
 */
trigger InterviewSharingTrigger on Interview__c(
  after insert,
  after update,
  after delete
) {
  InterviewSharingHandler handler = new InterviewSharingHandler();

  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      handler.onAfterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
      handler.onAfterDelete(Trigger.old);
    }
  }
}
