public with sharing class RecruitmentShortlistController {

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getMyShortlistedCandidates() {
        Id currentUserId = UserInfo.getUserId();

        return [
            SELECT Id,
                   Name,
                   Account.Name,
                   Job_Position__r.Name,
                   Hiring_Manager__c,
                   OwnerId,
                   Final_Applicant_Score__c,
                   Recruiter_Recommendation__c,
                   StageName,
                   Selection_Status__c,
                   Contract_Status__c,
                   LastModifiedDate
            FROM Opportunity
            WHERE StageName = 'Accepted'
              AND Selection_Status__c = 'Shortlisted'
              AND (OwnerId = :currentUserId OR Hiring_Manager__c = :currentUserId)
            ORDER BY Job_Position__r.Name, Final_Applicant_Score__c DESC, LastModifiedDate DESC
        ];
    }
}