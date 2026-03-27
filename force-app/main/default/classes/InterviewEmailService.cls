public without sharing class InterviewEmailService {

    private static final String OWE_ID = '0D2g50000000qppCAA';

    public static void sendInterviewInvitation(List<Interview__c> interviews) {
        if (interviews == null || interviews.isEmpty()) return;

        Set<Id> interviewIds = new Set<Id>();
        for (Interview__c i : interviews) interviewIds.add(i.Id);

        List<Interview__c> fullInterviews = [
            SELECT Id, Interview_Type__c, Interview_Date__c, End_Date_Time_c__c,
                   Interviewer__c, Interviewer__r.Name, Opportunity__c,
                   Opportunity__r.Name, Opportunity__r.Account.Name,
                   Opportunity__r.Account.PersonEmail
            FROM Interview__c
            WHERE Id IN :interviewIds
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Interview__c interview : fullInterviews) {
            String candidateEmail = interview.Opportunity__r.Account.PersonEmail;
            if (String.isBlank(candidateEmail)) continue;

            String candidateName = interview.Opportunity__r.Account.Name;
            String positionName = interview.Opportunity__r.Name;
            String interviewType = interview.Interview_Type__c != null ? interview.Interview_Type__c : 'HR';
            String interviewDate = interview.Interview_Date__c != null
                ? interview.Interview_Date__c.format('MMMM dd, yyyy') + ' at ' +
                  interview.Interview_Date__c.format('HH:mm')
                : 'To be confirmed';
            String interviewEndTime = interview.End_Date_Time_c__c != null
                ? interview.End_Date_Time_c__c.format('HH:mm') : 'To be confirmed';
            String interviewerName = interview.Interviewer__r != null
                ? interview.Interviewer__r.Name : 'TalentForce Team';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ candidateEmail });
            mail.setSubject('[' + interviewType + ' Interview] Invitation - ' + positionName);
            mail.setHtmlBody(
                TalentForceEmailTemplate.interviewInvitation(
                    candidateName, positionName, interviewType,
                    interviewDate, interviewEndTime, interviewerName
                )
            );
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('InterviewEmailService.sendInterviewInvitation email error: ' + e.getMessage());
            }
        }
    }

    public static void sendWithdrawnOrNoShowEmails(List<Interview__c> interviews) {
        if (interviews == null || interviews.isEmpty()) return;

        Set<Id> interviewIds = new Set<Id>();
        for (Interview__c i : interviews) interviewIds.add(i.Id);

        List<Interview__c> fullInterviews = [
            SELECT Id, Candidate_Withdrawn__c, No_Show__c, Opportunity__c,
                   Opportunity__r.Name, Opportunity__r.Account.Name,
                   Opportunity__r.Account.PersonEmail
            FROM Interview__c
            WHERE Id IN :interviewIds
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Interview__c interview : fullInterviews) {
            String candidateEmail = interview.Opportunity__r.Account.PersonEmail;
            if (String.isBlank(candidateEmail)) continue;

            String candidateName = interview.Opportunity__r.Account.Name;
            String positionName = interview.Opportunity__r.Name;
            String reason = interview.Candidate_Withdrawn__c ? 'withdrawn' : 'no_show';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ candidateEmail });
            mail.setSubject('Application Update - ' + positionName);
            mail.setHtmlBody(
                TalentForceEmailTemplate.rejected(candidateName, positionName, reason)
            );
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('InterviewEmailService.sendWithdrawnOrNoShowEmails email error: ' + e.getMessage());
            }
        }
    }
}