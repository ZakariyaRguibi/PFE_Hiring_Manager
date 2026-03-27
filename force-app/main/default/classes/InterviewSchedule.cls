public class InterviewSchedule {

    public class Input {
        @InvocableVariable(label='Interviewer Id' required=false)
        public String interviewerId;
    }

    public class Output {
        @InvocableVariable(label='Interview Schedule Summary')
        public String scheduleSummary;
    }

    @InvocableMethod(label='Get Interview Schedule' description='Returns the upcoming interview schedule for the currently logged-in interviewer.')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();

        try {
            String userId = inputs[0].interviewerId != null 
    ? inputs[0].interviewerId 
    : UserInfo.getUserId();

            List<Interview__c> interviews = [
                SELECT Id,
                       Name,
                       Interview_Type__c,
                       Interview_Date__c,
                       Recommendation__c,
                       Notes__c,
                       No_Show__c,
                       Candidate_Withdrawn__c,
                       Opportunity__r.Name,
                       Opportunity__r.Job_Position__c,
                       Opportunity__r.Job_Position__r.Name,
                       Opportunity__r.Account.Name
                FROM Interview__c
                WHERE Interviewer__c = :userId
                AND Interview_Date__c >= TODAY
                AND No_Show__c = false
                AND Candidate_Withdrawn__c = false
                ORDER BY Interview_Date__c ASC
                LIMIT 20
            ];

            if (interviews.isEmpty()) {
                result.scheduleSummary = 'You have no upcoming interviews scheduled.';
            } else {
                String summary = 'Here are your upcoming interviews:\n\n';
                Integer count = 1;

                for (Interview__c iv : interviews) {
                    String candidateName = iv.Opportunity__r.Account.Name != null
                        ? iv.Opportunity__r.Account.Name
                        : 'Unknown Candidate';

                    String jobPosition = iv.Opportunity__r.Job_Position__r.Name != null
                        ? iv.Opportunity__r.Job_Position__r.Name
                        : 'Unknown Position';

                    String interviewDate = iv.Interview_Date__c != null
                        ? iv.Interview_Date__c.format('MMMM d, yyyy h:mm a', UserInfo.getTimeZone().getId())
                        : 'Date not set';

                    summary += count + '. ' + iv.Interview_Type__c + ' Interview\n';
                    summary += '   Candidate: ' + candidateName + '\n';
                    summary += '   Position: ' + jobPosition + '\n';
                    summary += '   Date: ' + interviewDate + '\n\n';

                    count++;
                }

                result.scheduleSummary = summary;
            }

        } catch (Exception e) {
            result.scheduleSummary = 'Error retrieving interview schedule: ' + e.getMessage();
        }

        return new List<Output>{ result };
    }
}