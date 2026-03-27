public without sharing class TfTrackController {

    public class ApplicationDTO {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String jobPositionName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String finalDecision;
    }

    public class InterviewDTO {
        @AuraEnabled public Id interviewId;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String interviewName;
        @AuraEnabled public Datetime interviewDate;
        @AuraEnabled public String interviewType;
        @AuraEnabled public String interviewerName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String jobPositionName;
    }

    public class CandidateProfileDTO {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
    }

    @AuraEnabled(cacheable=true)
public static CandidateProfileDTO getMyCandidateProfile() {
    if (UserInfo.getUserType() == 'Guest') {
        return null;
    }

    User u = [
        SELECT Id, FirstName, LastName, Email, ContactId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
    ];

    CandidateProfileDTO dto = new CandidateProfileDTO();
    dto.firstName = u.FirstName;
    dto.lastName = u.LastName;
    dto.email = u.Email;

    if (u.ContactId != null) {
        Contact c = [
            SELECT Id, FirstName, LastName, Phone, MobilePhone
            FROM Contact
            WHERE Id = :u.ContactId
            LIMIT 1
        ];

        if (String.isBlank(dto.firstName)) {
            dto.firstName = c.FirstName;
        }
        if (String.isBlank(dto.lastName)) {
            dto.lastName = c.LastName;
        }

        dto.phone = String.isNotBlank(c.MobilePhone) ? c.MobilePhone : c.Phone;
    }

    return dto;
}

    @AuraEnabled(cacheable=true)
    public static Boolean isGuest() {
        return UserInfo.getUserType() == 'Guest';
    }

    private static User getCurrentUserRecord() {
        return [
            SELECT Id, ContactId, AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<ApplicationDTO> getMyApplications() {
        User u = getCurrentUserRecord();

        if (u.AccountId == null) {
            return new List<ApplicationDTO>();
        }

        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate, Final_Decision__c,
                   Job_Position__r.Name
            FROM Opportunity
            WHERE AccountId = :u.AccountId
            ORDER BY CreatedDate DESC
        ];

        List<ApplicationDTO> results = new List<ApplicationDTO>();
        for (Opportunity o : opps) {
            ApplicationDTO dto = new ApplicationDTO();
            dto.opportunityId = o.Id;
            dto.opportunityName = o.Name;
            dto.jobPositionName = (o.Job_Position__r != null) ? o.Job_Position__r.Name : null;
            dto.stageName = o.StageName;
            dto.closeDate = o.CloseDate;
            dto.finalDecision = (String)o.get('Final_Decision__c');
            results.add(dto);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<InterviewDTO> getMyInterviews() {
        User u = getCurrentUserRecord();

        if (u.AccountId == null) {
            return new List<InterviewDTO>();
        }

        List<Interview__c> interviews = [
            SELECT Id, Name, Interview_Date__c, Interview_Type__c,
                Interviewer__r.FirstName,
                Interviewer__r.LastName,
                Interviewer__r.Name,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.Job_Position__r.Name
            FROM Interview__c
            WHERE Opportunity__r.AccountId = :u.AccountId
            ORDER BY Interview_Date__c ASC
        ];

        List<InterviewDTO> results = new List<InterviewDTO>();
        for (Interview__c i : interviews) {
            InterviewDTO dto = new InterviewDTO();
            dto.interviewId = i.Id;
            dto.opportunityId = i.Opportunity__c;
            dto.interviewName = i.Name;
            dto.interviewDate = i.Interview_Date__c;
            dto.interviewType = i.Interview_Type__c;
            if (i.Interviewer__r != null) {
                String firstName = i.Interviewer__r.FirstName;
                String lastName = i.Interviewer__r.LastName;

                if (String.isNotBlank(firstName) || String.isNotBlank(lastName)) {
                    dto.interviewerName = ((firstName != null ? firstName : '') + ' ' + (lastName != null ? lastName : '')).trim();
                } else {
                    dto.interviewerName = i.Interviewer__r.Name;
                }
            } else {
                dto.interviewerName = null;
            }           
            dto.opportunityName = (i.Opportunity__r != null) ? i.Opportunity__r.Name : null;
            dto.jobPositionName = (i.Opportunity__r != null && i.Opportunity__r.Job_Position__r != null)
                ? i.Opportunity__r.Job_Position__r.Name
                : null;
            results.add(dto);
        }
        return results;
    }

    @AuraEnabled
    public static void withdrawMyApplication(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Missing opportunity id.');
        }

        User u = getCurrentUserRecord();

        if (u.AccountId == null) {
            throw new AuraHandledException('No candidate account found for this user.');
        }

        Opportunity opp = [
            SELECT Id, AccountId, StageName, Final_Decision__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (opp.AccountId != u.AccountId) {
            throw new AuraHandledException('You can only withdraw your own application.');
        }

        Integer upcomingInterviews = [
            SELECT COUNT()
            FROM Interview__c
            WHERE Opportunity__c = :opp.Id
            AND Interview_Date__c > :System.now()
        ];

        if (upcomingInterviews == 0) {
            throw new AuraHandledException('This application has no upcoming interviews to withdraw.');
        }

        opp.StageName = 'Withdrawn';
opp.Final_Decision__c = 'Withdrawn';
update opp;
    }
}