public with sharing class InterviewerDashboardController {

    public class DashboardStat {
        @AuraEnabled public Integer upcomingInterviews;
        @AuraEnabled public Integer completedThisMonth;
        @AuraEnabled public Integer pendingScores;
        @AuraEnabled public Integer recommended;
    }

    public class InterviewItem {
        @AuraEnabled public String id;
        @AuraEnabled public String candidateName;
        @AuraEnabled public String role;
        @AuraEnabled public String type;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public Boolean isToday;
    }

    public class PendingScoreItem {
        @AuraEnabled public String id;
        @AuraEnabled public String candidateName;
        @AuraEnabled public String role;
        @AuraEnabled public String type;
        @AuraEnabled public String dateLabel;
    }

    public class AlertItem {
        @AuraEnabled public String id;
        @AuraEnabled public String message;
        @AuraEnabled public String severity;
    }

    public class DashboardData {
        @AuraEnabled public DashboardStat stats;
        @AuraEnabled public List<InterviewItem> upcomingInterviews;
        @AuraEnabled public List<InterviewItem> todaysInterviews;
        @AuraEnabled public List<PendingScoreItem> pendingScores;
        @AuraEnabled public List<AlertItem> alerts;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        data.stats = new DashboardStat();
        data.upcomingInterviews = new List<InterviewItem>();
        data.todaysInterviews = new List<InterviewItem>();
        data.pendingScores = new List<PendingScoreItem>();
        data.alerts = new List<AlertItem>();

        String userId = UserInfo.getUserId();
        Date todayDate = Date.today();
        Date firstDayOfMonth = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Datetime startOfMonth = Datetime.newInstance(firstDayOfMonth, Time.newInstance(0,0,0,0));
        Datetime startOfToday = Datetime.newInstance(todayDate, Time.newInstance(0,0,0,0));
        Datetime endOfToday = startOfToday.addDays(1);

        // KPI STATS
        data.stats.upcomingInterviews = [
            SELECT COUNT() FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c >= TODAY
            AND No_Show__c = false
            AND Candidate_Withdrawn__c = false
        ];

        data.stats.completedThisMonth = [
            SELECT COUNT() FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c >= :startOfMonth
            AND Interview_Score__c != null
        ];

        data.stats.pendingScores = [
            SELECT COUNT() FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c < TODAY
            AND Interview_Score__c = null
            AND No_Show__c = false
            AND Candidate_Withdrawn__c = false
        ];

        data.stats.recommended = [
            SELECT COUNT() FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Recommendation__c = 'Recommend'
            AND Interview_Date__c >= :startOfMonth
        ];

        // TODAY'S INTERVIEWS
        for (Interview__c iv : [
            SELECT Id, Interview_Type__c, Interview_Date__c,
                   Opportunity__r.Account.Name,
                   Opportunity__r.Job_Position__r.Name
            FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c >= :startOfToday
            AND Interview_Date__c < :endOfToday
            AND No_Show__c = false
            AND Candidate_Withdrawn__c = false
            ORDER BY Interview_Date__c ASC
        ]) {
            InterviewItem item = new InterviewItem();
            item.id = iv.Id;
            item.candidateName = iv.Opportunity__r != null ? iv.Opportunity__r.Account.Name : 'Unknown';
            item.role = (iv.Opportunity__r != null && iv.Opportunity__r.Job_Position__r != null)
                ? iv.Opportunity__r.Job_Position__r.Name : '';
            item.type = iv.Interview_Type__c;
            item.timeLabel = iv.Interview_Date__c != null
                ? iv.Interview_Date__c.format('hh:mm a') : 'No time';
            item.dateLabel = iv.Interview_Date__c != null
                ? iv.Interview_Date__c.format('dd/MM/yyyy') : '';
            item.isToday = true;
            data.todaysInterviews.add(item);
        }

        // UPCOMING INTERVIEWS (next 7 days excluding today)
        for (Interview__c iv : [
            SELECT Id, Interview_Type__c, Interview_Date__c,
                   Opportunity__r.Account.Name,
                   Opportunity__r.Job_Position__r.Name
            FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c >= :endOfToday
            AND Interview_Date__c <= :Datetime.newInstance(todayDate.addDays(7), Time.newInstance(23,59,59,0))
            AND No_Show__c = false
            AND Candidate_Withdrawn__c = false
            ORDER BY Interview_Date__c ASC
            LIMIT 5
        ]) {
            InterviewItem item = new InterviewItem();
            item.id = iv.Id;
            item.candidateName = iv.Opportunity__r != null ? iv.Opportunity__r.Account.Name : 'Unknown';
            item.role = (iv.Opportunity__r != null && iv.Opportunity__r.Job_Position__r != null)
                ? iv.Opportunity__r.Job_Position__r.Name : '';
            item.type = iv.Interview_Type__c;
            item.timeLabel = iv.Interview_Date__c != null
                ? iv.Interview_Date__c.format('hh:mm a') : 'No time';
            item.dateLabel = iv.Interview_Date__c != null
                ? iv.Interview_Date__c.format('EEE, MMM d') : '';
            item.isToday = false;
            data.upcomingInterviews.add(item);
        }

        // PENDING SCORES
        for (Interview__c iv : [
            SELECT Id, Interview_Type__c, Interview_Date__c,
                   Opportunity__r.Account.Name,
                   Opportunity__r.Job_Position__r.Name
            FROM Interview__c
            WHERE Interviewer__c = :userId
            AND Interview_Date__c < TODAY
            AND Interview_Score__c = null
            AND No_Show__c = false
            AND Candidate_Withdrawn__c = false
            ORDER BY Interview_Date__c DESC
            LIMIT 5
        ]) {
            PendingScoreItem item = new PendingScoreItem();
            item.id = iv.Id;
            item.candidateName = iv.Opportunity__r != null ? iv.Opportunity__r.Account.Name : 'Unknown';
            item.role = (iv.Opportunity__r != null && iv.Opportunity__r.Job_Position__r != null)
                ? iv.Opportunity__r.Job_Position__r.Name : '';
            item.type = iv.Interview_Type__c;
            item.dateLabel = iv.Interview_Date__c != null
                ? iv.Interview_Date__c.format('dd/MM/yyyy') : '';
            data.pendingScores.add(item);
        }

        // ALERTS
        // Pending scores alert
        if (data.stats.pendingScores > 0) {
            AlertItem a = new AlertItem();
            a.id = userId;
            a.message = 'You have ' + data.stats.pendingScores + ' interview(s) pending scoring.';
            a.severity = 'warning';
            data.alerts.add(a);
        }

        // Interview today alert
        if (!data.todaysInterviews.isEmpty()) {
            AlertItem a = new AlertItem();
            a.id = userId + '_today';
            a.message = 'You have ' + data.todaysInterviews.size() + ' interview(s) scheduled today.';
            a.severity = 'high';
            data.alerts.add(a);
        }

        return data;
    }
}