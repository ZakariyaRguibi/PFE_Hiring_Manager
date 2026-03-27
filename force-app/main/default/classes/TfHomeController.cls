public with sharing class TfHomeController {

    @AuraEnabled(cacheable=true)
    public static List<String> getDepartmentOptions() {
        // Picklist values from Job_Position__c.Department__c
        Schema.DescribeFieldResult d = Job_Position__c.Department__c.getDescribe();
        List<String> values = new List<String>();
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe.isActive()) values.add(pe.getLabel());
        }
        values.sort();
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getOpenJobsCount() {
        return (Integer) [
            SELECT COUNT()
            FROM Job_Position__c
            WHERE Status__c = 'Open'
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Job_Position__c> getFeaturedOpenJobs(Integer limitSize) {
        Integer lim = (limitSize == null || limitSize < 1) ? 6 : Math.min(limitSize, 12);
        return [
            SELECT Id, Name, Location__c, Department__c, Employment_Type__c, Status__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ];
    }
}