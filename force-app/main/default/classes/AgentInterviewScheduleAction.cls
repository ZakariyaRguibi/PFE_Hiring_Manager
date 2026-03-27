public without sharing class AgentInterviewScheduleAction {

    public class InterviewRequest {
        @InvocableVariable(required=true label='Candidate Name')
        public String candidateName;
    }

    public class InterviewResponse {
        @InvocableVariable(label='Interview Summary')
        public String interviewSummary;
    }

    @InvocableMethod(
        label='Get Interview Schedule For Agent'
        description='Use this action when a user asks about interview schedules for a candidate.'
    )
    public static List<InterviewResponse> getInterviewSchedule(List<InterviewRequest> requests) {
        InterviewResponse response = new InterviewResponse();

        if (requests == null || requests.isEmpty() || String.isBlank(requests[0].candidateName)) {
            response.interviewSummary = 'No candidate name provided.';
            return new List<InterviewResponse>{ response };
        }

        String candidateName = requests[0].candidateName;

        // Get contact
        List<Contact> contacts = [
            SELECT Id, Name, AccountId
            FROM Contact
            WHERE Name LIKE :('%' + candidateName + '%')
            LIMIT 1
        ];

        if (contacts.isEmpty()) {
            response.interviewSummary = 'No candidate found with the name: ' + candidateName;
            return new List<InterviewResponse>{ response };
        }

        // Get opportunity
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, Job_Position__r.Name
            FROM Opportunity
            WHERE AccountId = :contacts[0].AccountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (opps.isEmpty()) {
            response.interviewSummary = 'No application found for candidate: ' + candidateName;
            return new List<InterviewResponse>{ response };
        }

        // Get interviews
        List<Interview__c> interviews = [
            SELECT Id,
                   Interview_Type__c,
                   Interview_Date__c,
                   End_Date_Time_c__c,
                   Interviewer__r.Name,
                   Interview_Score__c,
                   Recommendation__c,
                   Notes__c,
                   Opportunity__r.Name
            FROM Interview__c
            WHERE Opportunity__c = :opps[0].Id
            ORDER BY Interview_Date__c ASC
        ];

        if (interviews.isEmpty()) {
            response.interviewSummary = 'No interviews found for candidate: ' + candidateName + 
                                        ' applying for ' + opps[0].Name + '.';
            return new List<InterviewResponse>{ response };
        }

        // Build summary
        String summary = 'Interview schedule for ' + contacts[0].Name + 
                         ' — Position: ' + opps[0].Name + '\n\n';

        Integer index = 1;
        for (Interview__c iv : interviews) {
            summary += index + '. ' + (iv.Interview_Type__c != null ? iv.Interview_Type__c : 'Interview') + '\n';

            if (iv.Interview_Date__c != null) {
                summary += '   Date: ' + iv.Interview_Date__c.format('MMMM dd, yyyy') +
                           ' at ' + iv.Interview_Date__c.format('HH:mm') + '\n';
            }

            if (iv.Interviewer__r != null) {
                summary += '   Interviewer: ' + iv.Interviewer__r.Name + '\n';
            }

            if (iv.Interview_Score__c != null) {
                summary += '   Score: ' + iv.Interview_Score__c + '\n';
            }

            if (iv.Recommendation__c != null) {
                summary += '   Recommendation: ' + iv.Recommendation__c + '\n';
            }

            summary += '\n';
            index++;
        }

        response.interviewSummary = summary;
        return new List<InterviewResponse>{ response };
    }
}