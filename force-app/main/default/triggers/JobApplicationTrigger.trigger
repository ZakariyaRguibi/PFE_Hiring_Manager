trigger JobApplicationTrigger on Job_Application__c(
  before insert,
  after insert
) {
  JobApplicationTriggerHandler.handle(
    Trigger.new,
    Trigger.oldMap,
    Trigger.operationType
  );
}
