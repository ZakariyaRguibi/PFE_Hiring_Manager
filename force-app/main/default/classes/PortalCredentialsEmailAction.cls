public without sharing class PortalCredentialsEmailAction {

    private static final String OWE_ID = '0D2g50000000qppCAA';

    @InvocableMethod(label='Send Portal Credentials Email'
                     description='Sends branded credentials email to new Experience Cloud user')
    public static void sendPortalCredentialsFromFlow(List<CredentialsRequest> requests) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (CredentialsRequest req : requests) {
            if (String.isBlank(req.candidateEmail)) continue;

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ req.candidateEmail });
            mail.setSubject('Your TalentForce Portal Access');
            mail.setHtmlBody(
                TalentForceEmailTemplate.portalCredentials(
                    req.candidateName,
                    req.candidateEmail,
                    req.resetPasswordUrl != null ? req.resetPasswordUrl : ''
                )
            );
            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('PortalCredentialsEmailAction error: ' + e.getMessage());
            }
        }
    }

    public class CredentialsRequest {
        @InvocableVariable(required=true)
        public String candidateName;
        @InvocableVariable(required=true)
        public String candidateEmail;
        @InvocableVariable(required=false)
        public String resetPasswordUrl;
    }
}