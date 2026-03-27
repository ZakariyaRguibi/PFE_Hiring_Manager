public class PreInterviewCandidateBrief {

    public class Input {
        @InvocableVariable(label='Candidate Name' required=true)
        public String candidateName;

        @InvocableVariable(label='Interview Type' required=false)
        public String interviewType;

        @InvocableVariable(label='Job Position Name' required=false)
        public String jobPositionName;
    }

    public class Output {
        @InvocableVariable(label='Pre Interview Brief')
        public String interviewBrief;
    }

    @InvocableMethod(label='Get Pre Interview Candidate Brief' description='Returns a full pre-interview brief for the interviewer including candidate profile, job requirements, previous interviews, and suggested focus areas.')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();

        try {
            String candidateName = inputs[0].candidateName;
            String interviewType = inputs[0].interviewType;
            String jobPositionName = inputs[0].jobPositionName;

            // Build SOQL dynamically
            String query = 'SELECT Id, Name, StageName, ' +
                'Education_Score__c, Experience_Score__c, ' +
                'Interview_Score_Total__c, Final_Applicant_Score__c, ' +
                'Initial_Score__c, ' +
                'Job_Position__r.Name, ' +
                'Job_Position__r.Target_Skills__c, ' +
                'Job_Position__r.Min_Years_Experience__c, ' +
                'Job_Position__r.Education_Required__c, ' +
                'Job_Position__r.Department__c, ' +
                'Job_Position__r.Location__c, ' +
                'Account.Name, ' +
                'Account.PersonEmail, ' +
                'Assigned_Interviewer__r.Name, ' +
                '(SELECT Id, Interview_Type__c, Interview_Score__c, ' +
                'Recommendation__c, Notes__c, No_Show__c, ' +
                'Candidate_Withdrawn__c, Interviewer__r.Name, ' +
                'Interview_Date__c ' +
                'FROM Interviews__r ' +
                'ORDER BY Interview_Date__c ASC) ' +
                'FROM Opportunity ' +
                'WHERE Account.Name LIKE \'%' + String.escapeSingleQuotes(candidateName) + '%\' ' +
                'AND StageName NOT IN (\'Hired\', \'Withdrawn\', \'Rejected\')';

            if (String.isNotBlank(jobPositionName)) {
                query += ' AND Job_Position__r.Name LIKE \'%' + String.escapeSingleQuotes(jobPositionName) + '%\'';
            }

            query += ' LIMIT 5';

            List<Opportunity> apps = Database.query(query);

            if (apps.isEmpty()) {
                result.interviewBrief = 'No active application found for candidate "' + candidateName + '".';
                return new List<Output>{ result };
            }

            // Handle multiple applications
            if (apps.size() > 1 && String.isBlank(jobPositionName)) {
                String clarification = 'Multiple applications found for "' + candidateName + '". Please specify the job position:\n\n';
                Integer count = 1;
                for (Opportunity o : apps) {
                    clarification += count + '. ' + o.Job_Position__r.Name + ' — Stage: ' + o.StageName + '\n';
                    count++;
                }
                clarification += '\nPlease ask again with the candidate name and job position name.';
                result.interviewBrief = clarification;
                return new List<Output>{ result };
            }

            Opportunity app = apps[0];

            // Step 2: Find the original Lead using candidate email
            String candidateEmail = app.Account.PersonEmail;
            Lead originalLead = null;

            if (String.isNotBlank(candidateEmail)) {
                List<Lead> leads = [
                    SELECT Id, FirstName, LastName, Email,
                           Skills__c, Years_of_Experience__c,
                           Education_Level__c, CV_Link__c,
                           Motivation_Letter_Link__c
                    FROM Lead
                    WHERE Email = :candidateEmail
                    AND IsConverted = true
                    LIMIT 1
                ];
                if (!leads.isEmpty()) {
                    originalLead = leads[0];
                }
            }

            // Build direct link to Opportunity record
			String orgUrl = Url.getOrgDomainUrl().toExternalForm().replace('my.salesforce.com', 'lightning.force.com');
            String opportunityLink = orgUrl + '/' + app.Id;

            String brief = '';

            // Header
            brief += '📋 PRE-INTERVIEW BRIEF\n\n';
            brief += '🧑 CANDIDATE: ' + app.Account.Name + '\n';
            brief += '💼 POSITION: ' + app.Job_Position__r.Name + '\n';
            brief += '📊 CURRENT STAGE: ' + app.StageName + '\n';
            brief += '🔗 Application Record: ' + opportunityLink + '\n\n';

            // Candidate Profile from Lead
            brief += '👤 CANDIDATE PROFILE\n';
            if (originalLead != null) {
                brief += '   Education Level: ' + (String.isNotBlank(originalLead.Education_Level__c) ? originalLead.Education_Level__c : 'Not specified') + '\n';
                brief += '   Years of Experience: ' + (originalLead.Years_of_Experience__c != null ? String.valueOf(originalLead.Years_of_Experience__c) : 'Not specified') + '\n';
                brief += '   Skills: ' + (String.isNotBlank(originalLead.Skills__c) ? originalLead.Skills__c : 'Not specified') + '\n';
                brief += '   📁 CV & Motivation Letter: Open the Application Record above → go to Files section.\n';
            } else {
                brief += '   Education Score: ' + app.Education_Score__c + '\n';
                brief += '   Experience Score: ' + app.Experience_Score__c + '\n';
                brief += '   (Original lead profile not found)\n';
            }
            brief += '\n';

            // Job Requirements
            brief += '📋 JOB REQUIREMENTS\n';
            brief += '   Department: ' + app.Job_Position__r.Department__c + '\n';
            brief += '   Location: ' + app.Job_Position__r.Location__c + '\n';
            brief += '   Min Experience: ' + app.Job_Position__r.Min_Years_Experience__c + ' years\n';
            brief += '   Education Required: ' + app.Job_Position__r.Education_Required__c + '\n';
            brief += '   Target Skills: ' + app.Job_Position__r.Target_Skills__c + '\n\n';

            // Current Scores
            brief += '📈 CURRENT SCORES\n';
            brief += '   Education Score: ' + app.Education_Score__c + '\n';
            brief += '   Experience Score: ' + app.Experience_Score__c + '\n';
            brief += '   Interview Total Score: ' + app.Interview_Score_Total__c + '\n';
            brief += '   Final Applicant Score: ' + app.Final_Applicant_Score__c + '\n\n';

            // Previous Interview Results
            List<Interview__c> completedInterviews = new List<Interview__c>();
            Interview__c upcomingInterview = null;

            for (Interview__c iv : app.Interviews__r) {
                if (iv.Interview_Score__c != null || iv.No_Show__c || iv.Candidate_Withdrawn__c) {
                    completedInterviews.add(iv);
                } else if (upcomingInterview == null) {
                    upcomingInterview = iv;
                }
            }

            if (!completedInterviews.isEmpty()) {
                brief += '🎤 PREVIOUS INTERVIEW RESULTS\n';
                for (Interview__c iv : completedInterviews) {
                    if (iv.No_Show__c) {
                        brief += '   • ' + iv.Interview_Type__c + ' — NO SHOW\n';
                    } else if (iv.Candidate_Withdrawn__c) {
                        brief += '   • ' + iv.Interview_Type__c + ' — CANDIDATE WITHDRAWN\n';
                    } else {
                        brief += '   • ' + iv.Interview_Type__c + '\n';
                        brief += '     Score: ' + iv.Interview_Score__c + '\n';
                        brief += '     Recommendation: ' + iv.Recommendation__c + '\n';
                        brief += '     Notes: ' + (String.isNotBlank(iv.Notes__c) ? iv.Notes__c : 'No notes') + '\n\n';
                    }
                }
            } else {
                brief += '🎤 PREVIOUS INTERVIEWS\n   This is the first interview for this candidate.\n\n';
            }

            // Suggested Focus Areas based on Interview Type
            String ivType = String.isNotBlank(interviewType) ? interviewType :
                           (upcomingInterview != null ? upcomingInterview.Interview_Type__c : 'HR Interview');

            brief += '🎯 SUGGESTED FOCUS AREAS FOR ' + ivType.toUpperCase() + '\n';

            if (ivType == 'HR Interview') {
                brief += '   • Verify candidate motivation and cultural fit\n';
                brief += '   • Discuss career goals and expectations\n';
                brief += '   • Confirm availability, salary expectations, and notice period\n';
                brief += '   • Review any gaps or inconsistencies in the CV\n';
                brief += '   • Assess communication skills and professionalism\n';
            } else if (ivType == 'Technical Interview') {
                brief += '   • Test technical skills: ' + app.Job_Position__r.Target_Skills__c + '\n';
                brief += '   • Ask problem-solving and scenario-based questions\n';
                brief += '   • Assess depth of experience vs. required ' + app.Job_Position__r.Min_Years_Experience__c + ' years\n';
                brief += '   • Review any technical projects or past work\n';
                if (originalLead != null && String.isNotBlank(originalLead.Skills__c)) {
                    brief += '   • Candidate listed skills: ' + originalLead.Skills__c + ' — verify these in depth\n';
                }
            } else if (ivType == 'Manager Interview') {
                brief += '   • Assess leadership potential and team fit\n';
                brief += '   • Discuss past project ownership and decision-making\n';
                brief += '   • Review previous interview feedback and address any concerns\n';
                if (!completedInterviews.isEmpty()) {
                    brief += '   • Previous interviewers noted: ';
                    for (Interview__c iv : completedInterviews) {
                        if (String.isNotBlank(iv.Notes__c)) {
                            brief += iv.Notes__c + ' ';
                        }
                    }
                    brief += '\n';
                }
                brief += '   • Make final assessment on overall candidate suitability\n';
            }

            brief += '\n';
            result.interviewBrief = brief;

        } catch (Exception e) {
            result.interviewBrief = 'Error retrieving pre-interview brief: ' + e.getMessage();
        }

        return new List<Output>{ result };
    }
}