public with sharing class TfJobsController {

    @AuraEnabled(cacheable=true)
    public static List<String> getDepartmentOptions() {
        Schema.DescribeFieldResult d = Job_Position__c.Department__c.getDescribe();
        List<String> values = new List<String>();
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe.isActive()) values.add(pe.getLabel());
        }
        values.sort();
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getEmploymentTypeOptions() {
        Schema.DescribeFieldResult d = Job_Position__c.Employment_Type__c.getDescribe();
        List<String> values = new List<String>();
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe.isActive()) values.add(pe.getLabel());
        }
        values.sort();
        return values;
    }

    @AuraEnabled(cacheable=true)
public static List<Job_Position__c> searchOpenJobs(String keyword, String location, String department, String employmentType) {
    String k = '%' + (keyword == null ? '' : keyword.trim()) + '%';
    String loc = '%' + (location == null ? '' : location.trim()) + '%';

    String soql =
        'SELECT Id, Name, Location__c, Department__c, Employment_Type__c, Min_Years_Experience__c, Education_Required__c, Target_Skills__c, Status__c ' +
        'FROM Job_Position__c ' +
        'WHERE Status__c = \'Open\' ' +
        'AND (Name LIKE :k OR Department__c LIKE :k) ' +
        // location optional
        'AND (Location__c = null OR Location__c LIKE :loc) ';

    if (String.isNotBlank(department)) {
        soql += ' AND Department__c = :department ';
    }
    if (String.isNotBlank(employmentType)) {
        soql += ' AND Employment_Type__c = :employmentType ';
    }

    soql += ' ORDER BY CreatedDate DESC LIMIT 100';
    return Database.query(soql);
}
    @AuraEnabled(cacheable=true)
    public static Job_Position__c getJobById(Id jobId) {
        return [
            SELECT Id, Name, Location__c, Department__c, Employment_Type__c,
                   Min_Years_Experience__c, Education_Required__c, Target_Skills__c, Status__c
            FROM Job_Position__c
            WHERE Id = :jobId
            LIMIT 1
        ];
    }
}