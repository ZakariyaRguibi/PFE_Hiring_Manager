trigger RecruitmentOpportunityTrigger on Opportunity (after insert, after update) {
    if (RecruitmentHiringService.bypassTrigger) {
        return;
    }

    RecruitmentOpportunityTriggerHandler.handle(Trigger.oldMap, Trigger.newMap, Trigger.isInsert, Trigger.isUpdate);
}