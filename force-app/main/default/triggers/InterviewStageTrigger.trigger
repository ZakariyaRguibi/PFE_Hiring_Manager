trigger InterviewStageTrigger on Interview_Stage__c(
  before insert,
  before update
) {
  InterviewStageTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}