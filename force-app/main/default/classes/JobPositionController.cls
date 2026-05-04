public with sharing class JobPositionController {
  @AuraEnabled(cacheable=true)
  public static List<Job_Position__c> getJobPositions() {
    return [
      SELECT
        Id,
        Title__c,
        Department__c,
        Status__c,
        Required_Location__c,
        Open_Positions__c,
        Filled_Positions__c,
        Desired_Hires__c,
        Application_Deadline__c
      FROM Job_Position__c
      ORDER BY CreatedDate DESC
      LIMIT 200
    ];
  }
}
