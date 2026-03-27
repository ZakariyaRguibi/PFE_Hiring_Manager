public without sharing class RecruitmentEmailService {

    private static final String OWE_ID = '0D2g50000000qppCAA';

    private static Map<Id, Opportunity> getOpps(Set<Id> oppIds) {
        return new Map<Id, Opportunity>([
            SELECT Id, Name, Account.Name, Account.PersonEmail, Contract_Signed_Date__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ]);
    }

    public static void sendShortlistedEmails(Set<Id> oppIds) {
        Map<Id, Opportunity> opps = getOpps(oppIds);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : opps.values()) {
            if (opp.Account == null || String.isBlank(opp.Account.PersonEmail)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ opp.Account.PersonEmail });
            mail.setSubject('Your Application Has Been Shortlisted - ' + opp.Name);
            mail.setHtmlBody(TalentForceEmailTemplate.shortlisted(opp.Account.Name, opp.Name));
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('sendShortlistedEmails error: ' + e.getMessage());
            }
        }
    }

    public static void sendHiredEmails(Set<Id> oppIds) {
        Map<Id, Opportunity> opps = getOpps(oppIds);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : opps.values()) {
            if (opp.Account == null || String.isBlank(opp.Account.PersonEmail)) continue;

            String startDate = opp.Contract_Signed_Date__c != null
                ? opp.Contract_Signed_Date__c.format('MMMM dd, yyyy')
                : Date.today().format();

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ opp.Account.PersonEmail });
            mail.setSubject('Welcome to TalentForce! - ' + opp.Name);
            mail.setHtmlBody(TalentForceEmailTemplate.hired(opp.Account.Name, opp.Name, startDate));
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('sendHiredEmails error: ' + e.getMessage());
            }
        }
    }

    public static void sendRejectedEmails(Map<Id, String> oppIdToReason) {
        Map<Id, Opportunity> opps = getOpps(oppIdToReason.keySet());
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id oppId : oppIdToReason.keySet()) {
            Opportunity opp = opps.get(oppId);
            if (opp == null || opp.Account == null || String.isBlank(opp.Account.PersonEmail)) continue;

            String reason = oppIdToReason.get(oppId);
            String templateReason = 'standard';
            if (reason == 'Expired Contract') templateReason = 'expired';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ opp.Account.PersonEmail });
            mail.setSubject('Application Update - ' + opp.Name);
            mail.setHtmlBody(TalentForceEmailTemplate.rejected(opp.Account.Name, opp.Name, templateReason));
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('sendRejectedEmails error: ' + e.getMessage());
            }
        }
    }

    @InvocableMethod(label='Send Application Received Email'
                     description='Sends branded application received email to candidate')
    public static void sendApplicationReceivedFromFlow(List<ApplicationRequest> requests) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (ApplicationRequest req : requests) {
            if (String.isBlank(req.candidateEmail)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ req.candidateEmail });
            mail.setSubject('Application Received - ' + req.positionName);
            mail.setHtmlBody(
                TalentForceEmailTemplate.applicationReceived(req.candidateName, req.positionName)
            );
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('sendApplicationReceivedFromFlow error: ' + e.getMessage());
            }
        }
    }

    public class ApplicationRequest {
        @InvocableVariable(required=true)
        public String candidateName;
        @InvocableVariable(required=true)
        public String candidateEmail;
        @InvocableVariable(required=true)
        public String positionName;
    }
}