public with sharing class RecruitmentChatbotController {

    public class ChatRequest {
        @AuraEnabled public String message;
        @AuraEnabled public String conversationContext;
    }

    public class ChatResponse {
        @AuraEnabled public String response;
        @AuraEnabled public String intent;
    }

    @AuraEnabled
    public static ChatResponse processMessage(String userMessage, String context) {
        ChatResponse result = new ChatResponse();

        try {
            String msg = userMessage.toLowerCase();

            // Intent detection
            if (containsAny(msg, new List<String>{'job', 'position', 'match', 'recommend', 'opening', 'vacancy', 'apply', 'opportunity'})) {
                result.intent = 'JOB_RECOMMENDER';
                result.response = handleJobRecommender();

            } else if (containsAny(msg, new List<String>{'my interview', 'interview schedule', 'upcoming interview', 'when is my interview'})) {
                result.intent = 'INTERVIEW_SCHEDULE';
                result.response = handleInterviewSchedule();

            } else if (containsAny(msg, new List<String>{'application', 'status', 'stage', 'track', 'where is my'})) {
                result.intent = 'APPLICATION_STATUS';
                result.response = handleApplicationStatus();

            } else if (containsAny(msg, new List<String>{'withdraw', 'cancel', 'quit', 'remove my application'})) {
                result.intent = 'WITHDRAW';
                result.response = 'To withdraw your application, please go to the Track page and click the Withdraw button on your application.';

            } else if (containsAny(msg, new List<String>{'prepare', 'preparation', 'tips', 'advice', 'how to', 'hr interview', 'technical interview', 'manager interview'})) {
                result.intent = 'INTERVIEW_PREP';
                result.response = handleInterviewPrep(userMessage);

            } else if (containsAny(msg, new List<String>{'hello', 'hi', 'hey', 'good morning', 'good afternoon', 'bonjour', 'salut'})) {
                result.intent = 'GREETING';
                result.response = 'Hello! 👋 I\'m your TalentForce Recruitment Assistant. I can help you with:\n\n' +
                    '• 💼 Job recommendations based on your profile\n' +
                    '• 📊 Your application status\n' +
                    '• 📅 Your upcoming interviews\n' +
                    '• 🎯 Interview preparation tips\n\n' +
                    'What can I help you with today?';

            } else if (containsAny(msg, new List<String>{'help', 'what can you', 'what do you'})) {
                result.intent = 'HELP';
                result.response = 'I can help you with:\n\n' +
                    '• 💼 "What jobs match my profile?"\n' +
                    '• 📊 "What is my application status?"\n' +
                    '• 📅 "What are my upcoming interviews?"\n' +
                    '• 🎯 "How do I prepare for my HR interview?"\n\n' +
                    'Just type your question!';

            } else {
                result.intent = 'UNKNOWN';
                result.response = 'I\'m not sure I understood that. I can help you with job recommendations, application status, interview schedule, or interview preparation. What would you like to know?';
            }

        } catch (Exception e) {
            result.intent = 'ERROR';
            result.response = 'Sorry, something went wrong. Please try again.';
        }

        return result;
    }

    // Handle job recommendations
    private static String handleJobRecommender() {
        JobPositionRecommender.Input input = new JobPositionRecommender.Input();
        input.candidateUserId = UserInfo.getUserId();
        List<JobPositionRecommender.Output> results = JobPositionRecommender.execute(
            new List<JobPositionRecommender.Input>{ input }
        );
        return results[0].jobRecommendations;
    }

    // Handle interview schedule
    private static String handleInterviewSchedule() {
        InterviewSchedule.Input input = new InterviewSchedule.Input();
        List<InterviewSchedule.Output> results = InterviewSchedule.execute(
            new List<InterviewSchedule.Input>{ input }
        );
        return results[0].scheduleSummary;
    }

    // Handle application status
    private static String handleApplicationStatus() {
        // Get current user's contact
        List<User> users = [
            SELECT Id, ContactId, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].ContactId == null) {
            return 'No application found for your account.';
        }

        List<Opportunity> apps = [
            SELECT Id, Name, StageName,
                   Job_Position__r.Name,
                   Selection_Status__c,
                   Contract_Status__c
            FROM Opportunity
            WHERE AccountId IN (
                SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId
            )
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];

        if (apps.isEmpty()) {
            return 'You have no active applications at the moment.';
        }

        String summary = '📊 YOUR APPLICATION STATUS\n\n';
        for (Opportunity app : apps) {
            summary += '💼 ' + app.Job_Position__r.Name + '\n';
            summary += '   Stage: ' + app.StageName + '\n';
            if (String.isNotBlank(app.Selection_Status__c)) {
                summary += '   Status: ' + app.Selection_Status__c + '\n';
            }
            summary += '\n';
        }
        return summary;
    }

    // Handle interview preparation
    private static String handleInterviewPrep(String message) {
        String ivType = 'HR Interview';
        if (message.toLowerCase().contains('technical')) ivType = 'Technical Interview';
        else if (message.toLowerCase().contains('manager')) ivType = 'Manager Interview';

        String tips = '🎯 PREPARATION TIPS FOR ' + ivType.toUpperCase() + '\n\n';

        if (ivType == 'HR Interview') {
            tips += '✅ Research the company and role thoroughly\n';
            tips += '✅ Prepare your personal introduction (2-3 minutes)\n';
            tips += '✅ Be ready to discuss your career goals\n';
            tips += '✅ Prepare questions about the team and culture\n';
            tips += '✅ Know your salary expectations\n';
            tips += '✅ Dress professionally and arrive on time\n\n';
            tips += '💬 Common Questions:\n';
            tips += '• Tell me about yourself\n';
            tips += '• Why are you interested in this role?\n';
            tips += '• Where do you see yourself in 5 years?\n';
            tips += '• What are your strengths and weaknesses?\n';
        } else if (ivType == 'Technical Interview') {
            tips += '✅ Review core technical concepts for the role\n';
            tips += '✅ Practice problem-solving out loud\n';
            tips += '✅ Prepare examples of past technical projects\n';
            tips += '✅ Be ready to write or explain code/solutions\n';
            tips += '✅ Ask clarifying questions before answering\n\n';
            tips += '💬 Common Questions:\n';
            tips += '• Walk me through a technical project you built\n';
            tips += '• How would you solve [technical problem]?\n';
            tips += '• What technologies are you most comfortable with?\n';
        } else if (ivType == 'Manager Interview') {
            tips += '✅ Prepare examples of leadership and teamwork\n';
            tips += '✅ Be ready to discuss past challenges and solutions\n';
            tips += '✅ Show enthusiasm for the role and company\n';
            tips += '✅ Prepare thoughtful questions for the manager\n\n';
            tips += '💬 Common Questions:\n';
            tips += '• Tell me about a challenge you overcame\n';
            tips += '• How do you handle conflicts in a team?\n';
            tips += '• What motivates you professionally?\n';
        }

        return tips;
    }

    // Helper method
    private static Boolean containsAny(String text, List<String> keywords) {
        for (String keyword : keywords) {
            if (text.contains(keyword)) return true;
        }
        return false;
    }
}