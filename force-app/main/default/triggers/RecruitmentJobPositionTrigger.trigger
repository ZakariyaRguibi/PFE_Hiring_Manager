trigger RecruitmentJobPositionTrigger on Job_Position__c (after update) {
    if (RecruitmentHiringService.bypassJobPositionTrigger) {
        return;
    }

    RecruitmentJobPositionTriggerHandler.handle(Trigger.oldMap, Trigger.newMap);
}