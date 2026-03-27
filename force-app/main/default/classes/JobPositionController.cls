public with sharing class JobPositionController {

    @AuraEnabled(cacheable=true)
    public static List<Job_Position__c> getOpenJobs() {
        return [
            SELECT Id,
                   Name,
                   Location__c,
                   Department__c,
                   Employment_Type__c,
                   Min_Years_Experience__c,
                   Education_Required__c,
                   Target_Skills__c,
                   Status__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Job_Position__c getJobById(Id jobId) {
        return [
            SELECT Id,
                   Name,
                   Location__c,
                   Department__c,
                   Employment_Type__c,
                   Min_Years_Experience__c,
                   Education_Required__c,
                   Target_Skills__c,
                   Status__c
            FROM Job_Position__c
            WHERE Id = :jobId
            LIMIT 1
        ];
    }

}