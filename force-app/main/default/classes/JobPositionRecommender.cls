public class JobPositionRecommender {

    public class Input {
        @InvocableVariable(label='Candidate User Id' required=false)
        public String candidateUserId;
    }

    public class Output {
        @InvocableVariable(label='Job Recommendations')
        public String jobRecommendations;
    }

    @InvocableMethod(label='Get Job Position Recommendations' description='Recommends open job positions to a candidate based on their profile, skills, and experience.')
    public static List<Output> execute(List<Input> inputs) {
        Output result = new Output();

        try {
            String userId = (inputs[0].candidateUserId != null)
                ? inputs[0].candidateUserId
                : UserInfo.getUserId();

            // Step 1: Get Contact linked to portal user
            List<User> users = [
                SELECT Id, ContactId
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            if (users.isEmpty() || users[0].ContactId == null) {
                result.jobRecommendations = 'No candidate profile found for this user.';
                return new List<Output>{ result };
            }

            String contactId = users[0].ContactId;

            // Step 2: Get Contact email
            List<Contact> contacts = [
                SELECT Id, Email, Name
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];

            if (contacts.isEmpty()) {
                result.jobRecommendations = 'Candidate contact record not found.';
                return new List<Output>{ result };
            }

            Contact candidate = contacts[0];

            // Step 3: Trace back to original Lead
            Lead originalLead = null;

            if (String.isNotBlank(candidate.Email)) {
                List<Lead> leads = [
                    SELECT Id, Skills__c, Years_of_Experience__c,
                           Education_Level__c
                    FROM Lead
                    WHERE Email = :candidate.Email
                    AND IsConverted = true
                    LIMIT 1
                ];
                if (!leads.isEmpty()) {
                    originalLead = leads[0];
                }
            }

            // Step 4: Get open Job Positions
            List<Job_Position__c> openJobs = [
                SELECT Id, Name,
                       Department__c,
                       Location__c,
                       Employment_Type__c,
                       Min_Years_Experience__c,
                       Education_Required__c,
                       Target_Skills__c,
                       Salary__c,
                       Closure_Date__c,
                       Open_Positions__c
                FROM Job_Position__c
                WHERE Status__c = 'Open'
				AND (Closure_Date__c >= TODAY OR Closure_Date__c = null)
                ORDER BY Closure_Date__c ASC
                LIMIT 20
            ];

            if (openJobs.isEmpty()) {
                result.jobRecommendations = 'There are currently no open job positions available.';
                return new List<Output>{ result };
            }

            // Step 5: Build candidate profile text
            String candidateSkills = '';
            Integer candidateExperience = 0;
            String candidateEducation = '';

            if (originalLead != null) {
                candidateSkills = String.isNotBlank(originalLead.Skills__c) ? originalLead.Skills__c : '';
                candidateExperience = originalLead.Years_of_Experience__c != null
                    ? Integer.valueOf(originalLead.Years_of_Experience__c) : 0;
                candidateEducation = String.isNotBlank(originalLead.Education_Level__c)
                    ? originalLead.Education_Level__c : '';
            }

            // Step 6: Build recommendations
            String recommendations = '👋 Hello ' + candidate.Name + '! Here are the open positions that match your profile:\n\n';

            // Show candidate profile summary
            recommendations += '📋 YOUR PROFILE\n';
            recommendations += '   Education: ' + (String.isNotBlank(candidateEducation) ? candidateEducation : 'Not specified') + '\n';
            recommendations += '   Experience: ' + candidateExperience + ' years\n';
            recommendations += '   Skills: ' + (String.isNotBlank(candidateSkills) ? candidateSkills : 'Not specified') + '\n\n';

            recommendations += '💼 RECOMMENDED POSITIONS\n\n';

            Integer matchCount = 0;

            for (Job_Position__c job : openJobs) {
                // Calculate match
                Boolean experienceMatch = candidateExperience >= job.Min_Years_Experience__c;
                Boolean educationMatch = isEducationMatch(candidateEducation, job.Education_Required__c);
                List<String> matchedSkills = new List<String>();
                List<String> missingSkills = new List<String>();

                if (String.isNotBlank(job.Target_Skills__c) && String.isNotBlank(candidateSkills)) {
                    List<String> requiredSkills = job.Target_Skills__c.split(',');
                    for (String skill : requiredSkills) {
                        String trimmed = skill.trim().toLowerCase();
                        if (candidateSkills.toLowerCase().contains(trimmed)) {
                            matchedSkills.add(skill.trim());
                        } else {
                            missingSkills.add(skill.trim());
                        }
                    }
                }

                // Determine match level
                Integer matchScore = 0;
                if (experienceMatch) matchScore += 2;
                if (educationMatch) matchScore += 2;
                matchScore += matchedSkills.size();

                // Only show positions with at least partial match
                if (matchScore == 0 && originalLead != null) continue;

                String matchLabel = '';
                if (matchScore >= 4) matchLabel = '🟢 Strong Match';
                else if (matchScore >= 2) matchLabel = '🟡 Partial Match';
                else matchLabel = '🔴 Low Match';

                recommendations += matchLabel + ' — ' + job.Name + '\n';
                recommendations += '   📍 ' + job.Location__c + ' | ' + job.Department__c + ' | ' + job.Employment_Type__c + '\n';
                recommendations += '   💰 Salary: ' + (job.Salary__c != null ? String.valueOf(job.Salary__c) : 'Not specified') + '\n';
                recommendations += '   🎓 Education Required: ' + job.Education_Required__c + '\n';
                recommendations += '   ⏳ Min Experience: ' + job.Min_Years_Experience__c + ' years\n';

                // Match explanation
                recommendations += '   ✅ Experience: ' + (experienceMatch ? 'Matches (' + candidateExperience + ' years)' : 'Below requirement (' + candidateExperience + ' vs ' + job.Min_Years_Experience__c + ' required)') + '\n';
                recommendations += '   ✅ Education: ' + (educationMatch ? 'Matches' : 'May not meet requirement') + '\n';

                if (!matchedSkills.isEmpty()) {
                    recommendations += '   ✅ Matching Skills: ' + String.join(matchedSkills, ', ') + '\n';
                }
                if (!missingSkills.isEmpty()) {
                    recommendations += '   ⚠️ Skills Gap: ' + String.join(missingSkills, ', ') + '\n';
                }

				recommendations += '   📅 Apply before: ' + (job.Closure_Date__c != null ? job.Closure_Date__c.format() : 'No deadline set') + '\n\n';
                matchCount++;
            }

            if (matchCount == 0) {
                recommendations += 'No strong matches found based on your current profile. ';
                recommendations += 'Here are all open positions you can explore:\n\n';
                for (Job_Position__c job : openJobs) {
                    recommendations += '   • ' + job.Name + ' — ' + job.Location__c + ' | ' + job.Department__c + '\n';
                }
            }

            result.jobRecommendations = recommendations;

        } catch (Exception e) {
            result.jobRecommendations = 'Error retrieving job recommendations: ' + e.getMessage();
        }

        return new List<Output>{ result };
    }

    // Helper: check if candidate education meets job requirement
    private static Boolean isEducationMatch(String candidateEdu, String requiredEdu) {
        if (String.isBlank(candidateEdu) || String.isBlank(requiredEdu)) return false;

        Map<String, Integer> eduRank = new Map<String, Integer>{
            'High School' => 1,
            'Bachelor' => 2,
            'Master' => 3,
            'PhD' => 4
        };

        Integer candidateRank = eduRank.containsKey(candidateEdu) ? eduRank.get(candidateEdu) : 0;
        Integer requiredRank = eduRank.containsKey(requiredEdu) ? eduRank.get(requiredEdu) : 0;

        return candidateRank >= requiredRank;
    }
}