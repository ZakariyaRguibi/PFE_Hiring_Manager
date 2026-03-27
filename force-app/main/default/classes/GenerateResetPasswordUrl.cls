public without sharing class GenerateResetPasswordUrl {

    public class Input {
        @InvocableVariable(required=true)
        public String userId;
    }

    public class Output {
        @InvocableVariable(label='Reset Password URL')
        public String resetPasswordUrl;
    }

    @InvocableMethod(label='Generate Reset Password URL')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();
        try {
            String userId = inputs[0].userId;
            
            // Get user's username
            User u = [SELECT Id, Username FROM User WHERE Id = :userId LIMIT 1];
            
            // Trigger Salesforce's built-in forgot password email
            // This sends a real reset link to the user's email automatically
            Site.forgotPassword(u.Username);
            
            // Return just the login page URL
            result.resetPasswordUrl = 'https://orgfarm-5291b3907e-dev-ed.develop.my.site.com/recruitemntportal/s/login';
            
        } catch(Exception e) {
            result.resetPasswordUrl = 'https://orgfarm-5291b3907e-dev-ed.develop.my.site.com/recruitemntportal/s/login';
        }
        return new List<Output>{ result };
    }
}