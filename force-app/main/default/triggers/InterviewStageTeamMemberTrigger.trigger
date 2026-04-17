trigger InterviewStageTeamMemberTrigger on Interview_Stage_Team_Member__c(
  before insert,
  before update
) {
  InterviewStageTeamMemberTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}
