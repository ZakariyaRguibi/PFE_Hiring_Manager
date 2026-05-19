trigger JobApplicationTrigger on Job_Application__c(
  before insert,
  before update,
  after insert,
  after update
) {
  JobApplicationTriggerHandler.handle(
    Trigger.new,
    Trigger.oldMap,
    Trigger.operationType
  );
}
