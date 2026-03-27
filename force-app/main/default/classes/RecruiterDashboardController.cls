public with sharing class RecruiterDashboardController {

    public class DashboardStat {
        @AuraEnabled public Integer activeApplications;
        @AuraEnabled public Integer newApplicationsToday;
        @AuraEnabled public Integer interviewsToday;
        @AuraEnabled public Integer hiredThisMonth;
    }

    public class PipelineItem {
        @AuraEnabled public String stage;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal percentage;
    }

    public class CandidateItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String stage;
    }

    public class InterviewItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String type;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public String interviewer;
    }

    public class OpportunityItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String stage;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public Decimal score;
    }

    public class AlertItem {
        @AuraEnabled public String id;
        @AuraEnabled public String message;
        @AuraEnabled public String severity;
    }

    public class DashboardData {
        @AuraEnabled public DashboardStat stats;
        @AuraEnabled public List<PipelineItem> pipeline;
        @AuraEnabled public List<CandidateItem> topCandidates;
        @AuraEnabled public List<InterviewItem> interviews;
        @AuraEnabled public List<OpportunityItem> recentOpportunities;
        @AuraEnabled public List<AlertItem> alerts;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();
        data.stats = new DashboardStat();
        data.pipeline = new List<PipelineItem>();
        data.topCandidates = new List<CandidateItem>();
        data.interviews = new List<InterviewItem>();
        data.recentOpportunities = new List<OpportunityItem>();
        data.alerts = new List<AlertItem>();

        Date todayDate = Date.today();
        Datetime startOfToday = Datetime.newInstance(todayDate, Time.newInstance(0, 0, 0, 0));
        Datetime endOfToday = startOfToday.addDays(1);

        Date firstDayOfMonth = Date.newInstance(todayDate.year(), todayDate.month(), 1);
        Datetime startOfMonth = Datetime.newInstance(firstDayOfMonth, Time.newInstance(0, 0, 0, 0));

        List<String> closedStages = new List<String>{
            'Hired',
            'Rejected',
            'Withdrawn'
        };

        List<String> pipelineStages = new List<String>{
            'New',
            'HR Interview',
            'Technical Interview',
            'Manager Interview',
            'Offer Approval',
            'Hired'
        };

        // KPI STATS

        data.stats.activeApplications = [
            SELECT COUNT()
            FROM Opportunity
            WHERE StageName NOT IN :closedStages
        ];

        data.stats.newApplicationsToday = [
            SELECT COUNT()
            FROM Opportunity
            WHERE CreatedDate >= :startOfToday
            AND CreatedDate < :endOfToday
        ];

        data.stats.interviewsToday = [
            SELECT COUNT()
            FROM Interview__c
            WHERE Interview_Date__c >= :startOfToday
            AND Interview_Date__c < :endOfToday
        ];

        data.stats.hiredThisMonth = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Final_Decision__c = 'Hired'
            AND LastModifiedDate >= :startOfMonth
        ];

        // PIPELINE

        Map<String, Integer> stageCountMap = new Map<String, Integer>();

        for (AggregateResult ar : [
            SELECT StageName stage, COUNT(Id) total
            FROM Opportunity
            WHERE StageName IN :pipelineStages
            GROUP BY StageName
        ]) {
            stageCountMap.put((String) ar.get('stage'), (Integer) ar.get('total'));
        }

        Integer maxCount = 1;
        for (String stageName : pipelineStages) {
            Integer countValue = stageCountMap.containsKey(stageName) ? stageCountMap.get(stageName) : 0;
            if (countValue > maxCount) {
                maxCount = countValue;
            }
        }

        for (String stageName : pipelineStages) {
            Integer countValue = stageCountMap.containsKey(stageName) ? stageCountMap.get(stageName) : 0;

            PipelineItem item = new PipelineItem();
            item.stage = stageName;
            item.count = countValue;
            item.percentage = maxCount > 0
                ? (Decimal.valueOf(countValue) / Decimal.valueOf(maxCount)) * 100
                : 0;

            data.pipeline.add(item);
        }

        // TOP CANDIDATES

        for (Opportunity opp : [
            SELECT Id, Name, StageName, Final_Applicant_Score__c,
                   Job_Position__r.Name
            FROM Opportunity
            WHERE Final_Applicant_Score__c != null
            ORDER BY Final_Applicant_Score__c DESC
            LIMIT 5
        ]) {
            CandidateItem c = new CandidateItem();
            c.id = opp.Id;
            c.name = opp.Name;
            c.role = opp.Job_Position__r != null ? opp.Job_Position__r.Name : '';
            c.score = opp.Final_Applicant_Score__c;
            c.stage = opp.StageName;
            data.topCandidates.add(c);
        }

        // TODAY'S INTERVIEWS

        for (Interview__c interview : [
            SELECT Id, Name, Interview_Type__c, Interview_Date__c,
                   Interviewer__r.Name,
                   Opportunity__r.Name,
                   Opportunity__r.Job_Position__r.Name
            FROM Interview__c
            WHERE Interview_Date__c >= :startOfToday
            AND Interview_Date__c < :endOfToday
            ORDER BY Interview_Date__c ASC
            LIMIT 10
        ]) {
            InterviewItem item = new InterviewItem();
            item.id = interview.Id;
            item.name = interview.Opportunity__r != null ? interview.Opportunity__r.Name : interview.Name;
            item.role = (interview.Opportunity__r != null && interview.Opportunity__r.Job_Position__r != null)
                ? interview.Opportunity__r.Job_Position__r.Name
                : '';
            item.type = interview.Interview_Type__c;
            item.interviewer = interview.Interviewer__r != null ? interview.Interviewer__r.Name : '';

            if (interview.Interview_Date__c != null) {
                item.timeLabel = interview.Interview_Date__c.format('hh:mm a');
            } else {
                item.timeLabel = 'No time';
            }

            data.interviews.add(item);
        }

        // RECENT APPLICATIONS

        for (Opportunity opp : [
            SELECT Id, Name, StageName, CreatedDate, Final_Applicant_Score__c,
                   Job_Position__r.Name
            FROM Opportunity
            ORDER BY CreatedDate DESC
            LIMIT 5
        ]) {
            OpportunityItem item = new OpportunityItem();
            item.id = opp.Id;
            item.name = opp.Name;
            item.role = opp.Job_Position__r != null ? opp.Job_Position__r.Name : '';
            item.stage = opp.StageName;
            item.score = opp.Final_Applicant_Score__c;
            item.dateLabel = opp.CreatedDate.format('dd/MM/yyyy');
            data.recentOpportunities.add(item);
        }

        // ALERTS

        // 1) Get active opportunities first
        List<Opportunity> activeOpportunities = [
            SELECT Id, Name, StageName, Assigned_Interviewer__c, Interview_Count_c__c
            FROM Opportunity
            WHERE StageName NOT IN :closedStages
            AND OwnerId = :UserInfo.getUserId()
            LIMIT 200
        ];

        Set<Id> activeOpportunityIds = new Set<Id>();
        for (Opportunity opp : activeOpportunities) {
            activeOpportunityIds.add(opp.Id);
        }

        // 2) Find which of them have open tasks
        Set<Id> opportunityIdsWithOpenTasks = new Set<Id>();
        if (!activeOpportunityIds.isEmpty()) {
            for (Task t : [
                SELECT Id, WhatId
                FROM Task
                WHERE IsClosed = false
                AND WhatId IN :activeOpportunityIds
            ]) {
                if (t.WhatId != null) {
                    opportunityIdsWithOpenTasks.add(t.WhatId);
                }
            }
        }

        // 3) Alert: no open tasks
        Integer noTaskAlerts = 0;
        for (Opportunity opp : activeOpportunities) {
            if (!opportunityIdsWithOpenTasks.contains(opp.Id) && noTaskAlerts < 5) {
                AlertItem a = new AlertItem();
                a.id = opp.Id;
                a.message = 'Application "' + opp.Name + '" has no open activities.';
                a.severity = 'warning';
                data.alerts.add(a);
                noTaskAlerts++;
            }
        }

        // 4) Alert: no assigned interviewer
        Integer noInterviewerAlerts = 0;
        for (Opportunity opp : activeOpportunities) {
            if (
                (opp.StageName == 'HR Interview' ||
                 opp.StageName == 'Technical Interview' ||
                 opp.StageName == 'Manager Interview') &&
                opp.Assigned_Interviewer__c == null &&
                noInterviewerAlerts < 5
            ) {
                AlertItem a = new AlertItem();
                a.id = opp.Id;
                a.message = 'Application "' + opp.Name + '" has no assigned interviewer.';
                a.severity = 'high';
                data.alerts.add(a);
                noInterviewerAlerts++;
            }
        }

        // 5) Alert: in interview stage but no interview scheduled
        Integer noInterviewAlerts = 0;
        for (Opportunity opp : activeOpportunities) {
            Decimal interviewCount = opp.Interview_Count_c__c == null ? 0 : opp.Interview_Count_c__c;

            if (
                (opp.StageName == 'HR Interview' ||
                 opp.StageName == 'Technical Interview' ||
                 opp.StageName == 'Manager Interview') &&
                interviewCount == 0 &&
                noInterviewAlerts < 5
            ) {
                AlertItem a = new AlertItem();
                a.id = opp.Id;
                a.message = 'Application "' + opp.Name + '" is in interview stage but has no interviews scheduled.';
                a.severity = 'warning';
                data.alerts.add(a);
                noInterviewAlerts++;
            }
        }

        return data;
    }
}