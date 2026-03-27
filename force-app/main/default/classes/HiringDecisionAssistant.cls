public class HiringDecisionAssistant {

    public class Input {
        @InvocableVariable(label='Candidate Name' required=true)
        public String candidateName;

        @InvocableVariable(label='Job Position Name' required=false)
        public String jobPositionName;
    }

    public class Output {
        @InvocableVariable(label='Hiring Decision Summary')
        public String decisionSummary;
    }

    @InvocableMethod(label='Get Hiring Decision Assistant' description='Returns an AI-assisted hiring recommendation for a candidate based on the logged-in user role.')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();

        try {
            String candidateName = inputs[0].candidateName;
            String jobPositionName = inputs[0].jobPositionName;

            // Get current user role
            User currentUser = [
                SELECT Id, Name, UserRole.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            String roleName = currentUser.UserRole != null ? currentUser.UserRole.Name : '';
            Boolean isHiringManager = roleName == 'Hiring_Manager';
            Boolean isRecruiter = roleName == 'Recruiter';

            // If role is null (agent user context), default to Recruiter view
            if (!isHiringManager && !isRecruiter) {
                isRecruiter = true;
            }

            // Build SOQL to find candidate Opportunity
            String query = 'SELECT Id, Name, StageName, ' +
                'Education_Score__c, Experience_Score__c, ' +
                'Interview_Score__c, Interview_Score_Total__c, ' +
                'Final_Applicant_Score__c, ' +
                'Recruiter_Recommendation__c, ' +
                'Offer_Approval_Status__c, ' +
                'Selection_Status__c, ' +
                'Final_Decision__c, ' +
                'Job_Position__r.Name, ' +
                'Job_Position__r.Target_Skills__c, ' +
                'Job_Position__r.Min_Years_Experience__c, ' +
                'Job_Position__r.Education_Required__c, ' +
                'Account.Name, ' +
                'Hiring_Manager__r.Name, ' +
                'OwnerId, Owner.Name, ' +
                '(SELECT Id, Interview_Type__c, Interview_Score__c, ' +
                'Recommendation__c, Notes__c, No_Show__c, ' +
                'Candidate_Withdrawn__c, Interviewer__r.Name ' +
                'FROM Interviews__r ORDER BY Interview_Date__c ASC) ' +
                'FROM Opportunity ' +
                'WHERE Account.Name LIKE \'%' + String.escapeSingleQuotes(candidateName) + '%\'';

            if (String.isNotBlank(jobPositionName)) {
                query += ' AND Job_Position__r.Name LIKE \'%' + String.escapeSingleQuotes(jobPositionName) + '%\'';
            }

            query += ' AND StageName NOT IN (\'Hired\', \'Withdrawn\') LIMIT 5';

            List<Opportunity> apps = Database.query(query);

            if (apps.isEmpty()) {
                result.decisionSummary = 'No active application found for candidate "' + candidateName + '".';
                return new List<Output>{ result };
            }

            // If multiple applications found and no position specified, ask user to clarify
            if (apps.size() > 1 && String.isBlank(jobPositionName)) {
                String clarification = 'Multiple applications found for "' + candidateName + '". Please specify the job position:\n\n';
                Integer count = 1;
                for (Opportunity o : apps) {
                    clarification += count + '. ' + o.Job_Position__r.Name + ' — Stage: ' + o.StageName + '\n';
                    count++;
                }
                clarification += '\nPlease ask again with the candidate name and job position name.';
                result.decisionSummary = clarification;
                return new List<Output>{ result };
            }

            Opportunity app = apps[0];
            String summary = '';

            // Header
            summary += '🧑 CANDIDATE: ' + app.Account.Name + '\n';
            summary += '💼 POSITION: ' + app.Job_Position__r.Name + '\n';
            summary += '📊 CURRENT STAGE: ' + app.StageName + '\n\n';

            // Job Requirements
            summary += '📋 JOB REQUIREMENTS\n';
            summary += '   Min Experience: ' + app.Job_Position__r.Min_Years_Experience__c + ' years\n';
            summary += '   Education Required: ' + app.Job_Position__r.Education_Required__c + '\n';
            summary += '   Target Skills: ' + app.Job_Position__r.Target_Skills__c + '\n\n';

            // Scores
            summary += '📈 SCORES\n';
            summary += '   Education Score: ' + app.Education_Score__c + '\n';
            summary += '   Experience Score: ' + app.Experience_Score__c + '\n';
            summary += '   Interview Total Score: ' + app.Interview_Score_Total__c + '\n';
            summary += '   Final Applicant Score: ' + app.Final_Applicant_Score__c + '\n\n';

            // Interview Details
            if (!app.Interviews__r.isEmpty()) {
                summary += '🎤 INTERVIEW RESULTS\n';
                for (Interview__c iv : app.Interviews__r) {
                    if (iv.No_Show__c) {
                        summary += '   • ' + iv.Interview_Type__c + ' — NO SHOW\n';
                    } else if (iv.Candidate_Withdrawn__c) {
                        summary += '   • ' + iv.Interview_Type__c + ' — CANDIDATE WITHDRAWN\n';
                    } else {
                        summary += '   • ' + iv.Interview_Type__c + '\n';
                        summary += '     Score: ' + iv.Interview_Score__c + '\n';
                        summary += '     Recommendation: ' + iv.Recommendation__c + '\n';
                        summary += '     Notes: ' + (String.isNotBlank(iv.Notes__c) ? iv.Notes__c : 'No notes') + '\n';
                        summary += '     Interviewer: ' + iv.Interviewer__r.Name + '\n\n';
                    }
                }
            } else {
                summary += '🎤 INTERVIEW RESULTS\n   No interviews completed yet.\n\n';
            }

            // Recruiter Recommendation (only for Hiring Manager)
            if (isHiringManager) {
                summary += '👤 RECRUITER RECOMMENDATION\n';
                summary += '   ' + (String.isNotBlank(app.Recruiter_Recommendation__c)
                    ? app.Recruiter_Recommendation__c
                    : 'Not submitted yet') + '\n\n';
            }

            // AI Recommendation
            summary += '🤖 AI RECOMMENDATION\n';

            Integer recommendCount = 0;
            Integer notRecommendCount = 0;

            for (Interview__c iv : app.Interviews__r) {
                if (!iv.No_Show__c && !iv.Candidate_Withdrawn__c && iv.Interview_Score__c != null) {
                    if (iv.Recommendation__c == 'Recommend') recommendCount++;
                    if (iv.Recommendation__c == 'Not Recommend') notRecommendCount++;
                }
            }

            Decimal finalScore = app.Final_Applicant_Score__c != null ? app.Final_Applicant_Score__c : 0;

            if (finalScore >= 75 && recommendCount >= 2) {
                summary += '   ✅ STRONG HIRE — High scores across all dimensions';
                if (isHiringManager && app.Recruiter_Recommendation__c == 'Recommend') {
                    summary += ' and recruiter recommends this candidate.';
                }
            } else if (finalScore >= 60 && notRecommendCount == 0) {
                summary += '   🟡 CONSIDER — Decent scores with no major red flags.';
                if (isHiringManager && app.Recruiter_Recommendation__c == 'Not Recommend') {
                    summary += ' However, recruiter does not recommend — review carefully.';
                }
            } else if (notRecommendCount >= 2 || finalScore < 40) {
                summary += '   ❌ NOT RECOMMENDED — Low scores or multiple negative interview recommendations.';
            } else {
                summary += '   🟡 BORDERLINE — Mixed signals. Review interview notes carefully before deciding.';
            }

            summary += '\n';

            result.decisionSummary = summary;

        } catch (Exception e) {
            result.decisionSummary = 'Error retrieving hiring decision: ' + e.getMessage();
        }

        return new List<Output>{ result };
    }
}