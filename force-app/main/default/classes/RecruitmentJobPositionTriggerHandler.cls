public with sharing class RecruitmentJobPositionTriggerHandler {

    public static void handle(
        Map<Id, Job_Position__c> oldMap,
        Map<Id, Job_Position__c> newMap
    ) {
        Set<Id> jobIdsToFinalize = new Set<Id>();

        for (Id jobId : newMap.keySet()) {
            Job_Position__c newJob = newMap.get(jobId);
            Job_Position__c oldJob = oldMap.get(jobId);

            if (newJob.Finalize_Selection__c == true &&
                (oldJob == null || oldJob.Finalize_Selection__c != true)) {
                jobIdsToFinalize.add(jobId);
            }
        }

        if (!jobIdsToFinalize.isEmpty()) {
            RecruitmentHiringService.finalizeSelectionForJobs(jobIdsToFinalize);
        }
    }
}