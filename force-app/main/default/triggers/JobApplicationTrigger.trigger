<<<<<<< feature/TF-014-hitl-filter-review
trigger JobApplicationTrigger on Job_Application__c(before insert, before update, after insert) {
  JobApplicationTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
=======
trigger JobApplicationTrigger on Job_Application__c(
  before insert,
  after insert
) {
  JobApplicationTriggerHandler.handle(
    Trigger.new,
    Trigger.oldMap,
    Trigger.operationType
  );
>>>>>>> dev
}
