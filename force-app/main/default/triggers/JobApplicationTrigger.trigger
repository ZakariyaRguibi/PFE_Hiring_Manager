trigger JobApplicationTrigger on Job_Application__c(
  before insert,
  before update,
  after insert
) {
  JobApplicationTriggerHandler.handle(
    Trigger.new,
    Trigger.oldMap,
    Trigger.operationType
  );
}
