public with sharing class HiringManagerDashboardController {

    public class DashboardStat {
        @AuraEnabled public Integer pendingApprovals;
        @AuraEnabled public Integer approvedThisMonth;
        @AuraEnabled public Integer rejectedThisMonth;
        @AuraEnabled public Integer activePositions;
    }

    public class ApprovalItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String stage;
        @AuraEnabled public String recruiterRecommendation;
    }

    public class TopCandidateItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String status;
    }

    public class PositionItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String department;
        @AuraEnabled public String closureLabel;
        @AuraEnabled public Integer openPositions;
        @AuraEnabled public Integer filledPositions;
        @AuraEnabled public Boolean isUrgent;
    }

    public class AlertItem {
        @AuraEnabled public String id;
        @AuraEnabled public String message;
        @AuraEnabled public String severity;
    }

    public class DashboardData {
        @AuraEnabled public DashboardStat stats;
        @AuraEnabled public List<ApprovalItem> approvalQueue;
        @AuraEnabled public List<TopCandidateItem> topCandidates;
        @AuraEnabled public List<PositionItem> positions;
        @AuraEnabled public List<AlertItem> alerts;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        data.stats = new DashboardStat();
        data.approvalQueue = new List<ApprovalItem>();
        data.topCandidates = new List<TopCandidateItem>();
        data.positions = new List<PositionItem>();
        data.alerts = new List<AlertItem>();

        Date todayDate = Date.today();
        Date firstDayOfMonth = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Datetime startOfMonth = Datetime.newInstance(firstDayOfMonth, Time.newInstance(0,0,0,0));
        String hmId = UserInfo.getUserId();

        // KPI STATS
        data.stats.pendingApprovals = [
            SELECT COUNT() FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND Offer_Approval_Status__c = 'Pending Approval'
        ];

        data.stats.approvedThisMonth = [
            SELECT COUNT() FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND Offer_Approval_Status__c = 'Approved'
            AND LastModifiedDate >= :startOfMonth
        ];

        data.stats.rejectedThisMonth = [
            SELECT COUNT() FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND Offer_Approval_Status__c = 'Rejected'
            AND LastModifiedDate >= :startOfMonth
        ];

        data.stats.activePositions = [
            SELECT COUNT() FROM Job_Position__c
            WHERE Status__c = 'Open'
        ];

        // APPROVAL QUEUE
        for (Opportunity opp : [
            SELECT Id, Name, StageName,
                   Final_Applicant_Score__c,
                   Recruiter_Recommendation__c,
                   Job_Position__r.Name,
                   Account.Name
            FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND Offer_Approval_Status__c = 'Pending Approval'
            ORDER BY Final_Applicant_Score__c DESC NULLS LAST
            LIMIT 10
        ]) {
            ApprovalItem item = new ApprovalItem();
            item.id = opp.Id;
            item.name = opp.Account.Name;
            item.role = opp.Job_Position__r != null ? opp.Job_Position__r.Name : '';
            item.score = opp.Final_Applicant_Score__c;
            item.stage = opp.StageName;
            item.recruiterRecommendation = opp.Recruiter_Recommendation__c;
            data.approvalQueue.add(item);
        }

        // TOP CANDIDATES (Acceptance Pool)
        for (Opportunity opp : [
            SELECT Id, Name, StageName,
                   Final_Applicant_Score__c,
                   Selection_Status__c,
                   Job_Position__r.Name,
                   Account.Name
            FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND StageName = 'Accepted'
            ORDER BY Final_Applicant_Score__c DESC NULLS LAST
            LIMIT 5
        ]) {
            TopCandidateItem item = new TopCandidateItem();
            item.id = opp.Id;
            item.name = opp.Account.Name;
            item.role = opp.Job_Position__r != null ? opp.Job_Position__r.Name : '';
            item.score = opp.Final_Applicant_Score__c;
            item.status = opp.Selection_Status__c;
            data.topCandidates.add(item);
        }

        // POSITIONS
        for (Job_Position__c pos : [
            SELECT Id, Name, Department__c,
                   Closure_Date__c,
                   Open_Positions__c,
                   Filled_Positions__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            ORDER BY Closure_Date__c ASC NULLS LAST
            LIMIT 5
        ]) {
            PositionItem item = new PositionItem();
            item.id = pos.Id;
            item.name = pos.Name;
            item.department = pos.Department__c;
            item.openPositions = pos.Open_Positions__c != null ? Integer.valueOf(pos.Open_Positions__c) : 0;
            item.filledPositions = pos.Filled_Positions__c != null ? Integer.valueOf(pos.Filled_Positions__c) : 0;
            item.closureLabel = pos.Closure_Date__c != null ? pos.Closure_Date__c.format() : 'No deadline';
            item.isUrgent = pos.Closure_Date__c != null && pos.Closure_Date__c <= todayDate.addDays(7);
            data.positions.add(item);
        }

        // ALERTS
        // Positions closing soon
        for (Job_Position__c pos : [
            SELECT Id, Name, Closure_Date__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            AND Closure_Date__c <= :todayDate.addDays(7)
            AND Closure_Date__c >= :todayDate
            LIMIT 3
        ]) {
            AlertItem a = new AlertItem();
            a.id = pos.Id;
            a.message = 'Position "' + pos.Name + '" closes on ' + pos.Closure_Date__c.format();
            a.severity = 'high';
            data.alerts.add(a);
        }

        // Candidates pending approval for more than 2 days
        Datetime twoDaysAgo = Datetime.now().addDays(-2);
        for (Opportunity opp : [
            SELECT Id, Name, Account.Name, Job_Position__r.Name
            FROM Opportunity
            WHERE Hiring_Manager__c = :hmId
            AND Offer_Approval_Status__c = 'Pending Approval'
            AND LastModifiedDate <= :twoDaysAgo
            LIMIT 3
        ]) {
            AlertItem a = new AlertItem();
            a.id = opp.Id;
            a.message = '"' + opp.Account.Name + '" has been waiting for your approval for over 2 days.';
            a.severity = 'warning';
            data.alerts.add(a);
        }

        return data;
    }
}