public with sharing class LeadMatchController {
    public class MatchInfo {
        @AuraEnabled public Boolean hasExisting;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountUrl;
    }

    @AuraEnabled(cacheable=true)
    public static MatchInfo getExistingAccountInfo(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('leadId is required');
        }

        Lead l = [
            SELECT Id, FirstName, LastName, Email, Existing_Person_Account__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        MatchInfo info = new MatchInfo();

        if (l.Existing_Person_Account__c != null) {
            Account a = [
                SELECT Id, Name
                FROM Account
                WHERE Id = :l.Existing_Person_Account__c
                LIMIT 1
            ];
            info.hasExisting = true;
            info.accountId = a.Id;
            info.accountName = a.Name;
            info.accountUrl = '/' + a.Id;
            return info;
        }

        
        List<Account> matches = [
            SELECT Id, Name
            FROM Account
            WHERE PersonEmail = :l.Email
            AND FirstName = :l.FirstName
            AND LastName = :l.LastName
            LIMIT 1
        ];

        if (!matches.isEmpty()) {
            Account a = matches[0];
            info.hasExisting = true;
            info.accountId = a.Id;
            info.accountName = a.Name;
            info.accountUrl = '/' + a.Id;
        } else {
            info.hasExisting = false;
        }

        return info;
    }
}