trigger InterviewTrigger on Interview__c(before insert, before update) {
  InterviewTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}
