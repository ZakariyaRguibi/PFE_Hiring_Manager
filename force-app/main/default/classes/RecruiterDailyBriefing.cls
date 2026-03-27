public class RecruiterDailyBriefing {

    public class Input {
        @InvocableVariable(label='Recruiter Id' required=false)
        public String recruiterId;
    }

    public class Output {
        @InvocableVariable(label='Daily Briefing Summary')
        public String briefingSummary;
    }

    @InvocableMethod(label='Get Recruiter Daily Briefing' description='Returns a daily briefing summary for the logged-in recruiter.')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();

        try {
            String userId = (inputs[0].recruiterId != null)
                ? inputs[0].recruiterId
                : UserInfo.getUserId();

            String recruiterName = UserInfo.getName();

            // 1. Pending Approvals
            List<Opportunity> pendingApprovals = [
                SELECT Id, Name, Account.Name, Job_Position__r.Name
                FROM Opportunity
                WHERE OwnerId = :userId
                AND Offer_Approval_Status__c = 'Pending Approval'
            ];

            // 2. Expiring Contracts (deadline today or tomorrow)
            DateTime todayStart = DateTime.newInstance(Date.today(), Time.newInstance(0,0,0,0));
            DateTime tomorrowEnd = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(0,0,0,0));

            List<Opportunity> expiringContracts = [
                SELECT Id, Name, Account.Name, Job_Position__r.Name, Contract_Deadline__c
                FROM Opportunity
                WHERE OwnerId = :userId
                AND Contract_Status__c = 'Sent'
                AND Contract_Deadline__c >= :todayStart
                AND Contract_Deadline__c < :tomorrowEnd
            ];

            // 3. Today's Interviews
            DateTime todayEnd = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(0,0,0,0));

            List<Interview__c> todaysInterviews = [
                SELECT Id, Interview_Type__c, Interview_Date__c,
                       Interviewer__r.Name,
                       Opportunity__r.Account.Name,
                       Opportunity__r.Job_Position__r.Name
                FROM Interview__c
                WHERE Opportunity__r.OwnerId = :userId
                AND Interview_Date__c >= :todayStart
                AND Interview_Date__c < :todayEnd
                ORDER BY Interview_Date__c ASC
            ];

            // 4. Candidates Awaiting Offer Approval Submission
            List<Opportunity> awaitingSubmission = [
                SELECT Id, Name, Account.Name, Job_Position__r.Name
                FROM Opportunity
                WHERE OwnerId = :userId
                AND StageName = 'Offer Approval'
                AND Offer_Approval_Status__c = 'Not Submitted'
            ];

            // 5. Accepted candidates waiting for contract
            List<Opportunity> acceptedNoContract = [
                SELECT Id, Name, Account.Name, Job_Position__r.Name
                FROM Opportunity
                WHERE OwnerId = :userId
                AND StageName = 'Accepted'
                AND Contract_Status__c = 'Not Sent'
            ];

            // Build the briefing
            String briefing = '📋 Good morning, ' + recruiterName + '! Here is your recruitment briefing for today:\n\n';

            // Section 1
            briefing += '✅ PENDING APPROVALS (' + pendingApprovals.size() + ')\n';
            if (pendingApprovals.isEmpty()) {
                briefing += '   No pending approvals.\n';
            } else {
                for (Opportunity o : pendingApprovals) {
                    briefing += '   • ' + o.Account.Name + ' — ' + o.Job_Position__r.Name + '\n';
                }
            }

            // Section 2
            briefing += '\n⏰ EXPIRING CONTRACTS TODAY/TOMORROW (' + expiringContracts.size() + ')\n';
            if (expiringContracts.isEmpty()) {
                briefing += '   No contracts expiring soon.\n';
            } else {
                for (Opportunity o : expiringContracts) {
                    String deadlineStr = o.Contract_Deadline__c != null
                        ? o.Contract_Deadline__c.format('MMMM d, yyyy h:mm a', UserInfo.getTimeZone().getId())
                        : 'No deadline set';
                    briefing += '   • ' + o.Account.Name + ' — ' + o.Job_Position__r.Name + ' (Deadline: ' + deadlineStr + ')\n';
                }
            }

            // Section 3
            briefing += '\n📅 TODAY\'S INTERVIEWS (' + todaysInterviews.size() + ')\n';
            if (todaysInterviews.isEmpty()) {
                briefing += '   No interviews scheduled for today.\n';
            } else {
                for (Interview__c iv : todaysInterviews) {
                    String ivTime = iv.Interview_Date__c != null
                        ? iv.Interview_Date__c.format('h:mm a', UserInfo.getTimeZone().getId())
                        : 'Time not set';
                    briefing += '   • ' + iv.Interview_Type__c + ' — ' + iv.Opportunity__r.Account.Name
                             + ' (' + iv.Opportunity__r.Job_Position__r.Name + ') at ' + ivTime
                             + ' with ' + iv.Interviewer__r.Name + '\n';
                }
            }

            // Section 4
            briefing += '\n📝 AWAITING APPROVAL SUBMISSION (' + awaitingSubmission.size() + ')\n';
            if (awaitingSubmission.isEmpty()) {
                briefing += '   No candidates waiting for approval submission.\n';
            } else {
                for (Opportunity o : awaitingSubmission) {
                    briefing += '   • ' + o.Account.Name + ' — ' + o.Job_Position__r.Name + '\n';
                }
            }

            // Section 5
            briefing += '\n📨 ACCEPTED CANDIDATES — CONTRACT NOT SENT (' + acceptedNoContract.size() + ')\n';
            if (acceptedNoContract.isEmpty()) {
                briefing += '   No accepted candidates waiting for a contract.\n';
            } else {
                for (Opportunity o : acceptedNoContract) {
                    briefing += '   • ' + o.Account.Name + ' — ' + o.Job_Position__r.Name + '\n';
                }
            }

            result.briefingSummary = briefing;

        } catch (Exception e) {
            result.briefingSummary = 'Error retrieving briefing: ' + e.getMessage();
        }

        return new List<Output>{ result };
    }
}