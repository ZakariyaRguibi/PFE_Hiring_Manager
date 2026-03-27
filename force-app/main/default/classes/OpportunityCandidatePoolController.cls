public with sharing class OpportunityCandidatePoolController {

    public class CandidateRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal score;
        @AuraEnabled public String selectionStatus;
        @AuraEnabled public String finalDecision;
        @AuraEnabled public String stageName;
    }

    public class CandidatePoolResponse {
        @AuraEnabled public String jobPositionName;
        @AuraEnabled public Integer openPositions;
        @AuraEnabled public Integer filledPositions;
        @AuraEnabled public Integer remainingPositions;
        @AuraEnabled public Integer totalApplicants;

        @AuraEnabled public List<CandidateRow> acceptedPool;
        @AuraEnabled public List<CandidateRow> shortlisted;
        @AuraEnabled public List<CandidateRow> hired;
        @AuraEnabled public List<CandidateRow> rejected;
    }

    @AuraEnabled(cacheable=true)
    public static CandidatePoolResponse getCandidatePool(Id recordId) {

        if (recordId == null) {
            return new CandidatePoolResponse();
        }

        Id jobPositionId;

        String objectName = recordId.getSObjectType().getDescribe().getName();

        if (objectName == 'Opportunity') {

            Opportunity opp = [
                SELECT Job_Position__c
                FROM Opportunity
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (opp.Job_Position__c == null) {
                return new CandidatePoolResponse();
            }

            jobPositionId = opp.Job_Position__c;

        } else if (objectName == 'Job_Position__c') {

            jobPositionId = recordId;

        } else {
            return new CandidatePoolResponse();
        }

        Job_Position__c job = [
            SELECT Name, Open_Positions__c, Filled_Positions__c
            FROM Job_Position__c
            WHERE Id = :jobPositionId
            LIMIT 1
        ];

        List<Opportunity> relatedOpps = [
            SELECT Id, Name, Account.Name, StageName,
                   Final_Decision__c, Selection_Status__c,
                   Final_Applicant_Score__c
            FROM Opportunity
            WHERE Job_Position__c = :jobPositionId
            ORDER BY Final_Applicant_Score__c DESC
        ];

        CandidatePoolResponse res = new CandidatePoolResponse();

        res.jobPositionName = job.Name;
        res.openPositions = toInt(job.Open_Positions__c);
        res.filledPositions = toInt(job.Filled_Positions__c);
        res.remainingPositions = Math.max(0, res.openPositions - res.filledPositions);
        res.totalApplicants = relatedOpps.size();

        res.acceptedPool = new List<CandidateRow>();
        res.shortlisted = new List<CandidateRow>();
        res.hired = new List<CandidateRow>();
        res.rejected = new List<CandidateRow>();

        for (Opportunity opp : relatedOpps) {

    CandidateRow row = new CandidateRow();
    row.id = opp.Id;
    row.name = opp.Name;
    row.accountName = opp.Account != null ? opp.Account.Name : '';
    row.score = opp.Final_Applicant_Score__c;
    row.selectionStatus = opp.Selection_Status__c;
    row.finalDecision = opp.Final_Decision__c;
    row.stageName = opp.StageName;

    if (opp.StageName == 'Hired') {
        res.hired.add(row);

    } else if (opp.StageName == 'Rejected' || opp.Final_Decision__c == 'Rejected') {
        res.rejected.add(row);

    } else if (opp.StageName == 'Accepted' && opp.Selection_Status__c == 'Shortlisted') {
        res.shortlisted.add(row);

    } else if (opp.StageName == 'Accepted') {
        res.acceptedPool.add(row);

    }
    // candidates in New, Screening, HR Interview, Offer Approval etc. are intentionally excluded
}

        return res;
    }

    private static Integer toInt(Decimal value) {
        return value == null ? 0 : Integer.valueOf(value.intValue());
    }
}