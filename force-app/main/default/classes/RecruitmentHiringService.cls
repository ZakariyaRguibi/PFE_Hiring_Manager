public without sharing class RecruitmentHiringService {

    public static Boolean bypassTrigger = false;
    public static Boolean bypassJobPositionTrigger = false;
    private static final String OWE_ID = '0D2g50000000qppCAA';

    public static void finalizeSelectionForJobs(Set<Id> jobPositionIds) {
        if (jobPositionIds == null || jobPositionIds.isEmpty()) return;

        Map<Id, Job_Position__c> jobsById = new Map<Id, Job_Position__c>([
            SELECT Id, Name, Open_Positions__c, Filled_Positions__c, Finalize_Selection__c
            FROM Job_Position__c
            WHERE Id IN :jobPositionIds
        ]);

        List<Opportunity> acceptedOpps = [
            SELECT Id, Name, AccountId, OwnerId, Hiring_Manager__c,
                   Job_Position__c, StageName, Final_Applicant_Score__c,
                   Selection_Status__c, Contract_Status__c, ContractId,
                   Contract_Signed__c, Offer_Approval_Status__c
            FROM Opportunity
            WHERE Job_Position__c IN :jobPositionIds
              AND StageName = 'Accepted'
            ORDER BY Job_Position__c, Final_Applicant_Score__c DESC, CreatedDate ASC
        ];

        Map<Id, List<Opportunity>> oppsByJob = new Map<Id, List<Opportunity>>();
        for (Opportunity opp : acceptedOpps) {
            if (!oppsByJob.containsKey(opp.Job_Position__c)) {
                oppsByJob.put(opp.Job_Position__c, new List<Opportunity>());
            }
            oppsByJob.get(opp.Job_Position__c).add(opp);
        }

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Set<Id> oppIdsToSendContract = new Set<Id>();

        for (Id jobId : jobsById.keySet()) {
            Job_Position__c job = jobsById.get(jobId);
            Integer openPositions = toInt(job.Open_Positions__c);
            Integer filledPositions = toInt(job.Filled_Positions__c);
            Integer availableSlots = Math.max(openPositions - filledPositions, 0);

            List<Opportunity> candidates = oppsByJob.containsKey(jobId)
                ? oppsByJob.get(jobId) : new List<Opportunity>();

            Integer rankCounter = 0;

            for (Opportunity opp : candidates) {
                Boolean isTopCandidate = rankCounter < availableSlots;

                if (isTopCandidate) {
                    if (opp.Selection_Status__c == null
                        || opp.Selection_Status__c == 'Shortlisted'
                        || opp.Selection_Status__c == 'Not Selected'
                        || opp.Selection_Status__c == 'Expired') {

                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Selected for Contract';
                        if (opp.Contract_Status__c == null
                            || opp.Contract_Status__c == 'Expired'
                            || opp.Contract_Status__c == 'Not Sent') {
                            upd.Contract_Status__c = 'Not Sent';
                        }
                        oppsToUpdate.add(upd);
                        oppIdsToSendContract.add(opp.Id);
                    }
                    rankCounter++;
                } else {
                    if (opp.Selection_Status__c == 'Selected for Contract'
                        || opp.Selection_Status__c == 'Contract Sent') {
                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Shortlisted';
                        upd.Contract_Status__c = 'Expired';
                        oppsToUpdate.add(upd);
                    } else if (opp.Selection_Status__c == null
                        || opp.Selection_Status__c == 'Not Selected'
                        || opp.Selection_Status__c == 'Expired') {
                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Shortlisted';
                        oppsToUpdate.add(upd);
                    }
                }
            }
        }

        if (!oppsToUpdate.isEmpty()) updateWithBypass(oppsToUpdate);
        if (!oppIdsToSendContract.isEmpty()) sendContractsForSelectedCandidates(oppIdsToSendContract);
        ensureHiringManagerShares(new Set<Id>(new Map<Id, Opportunity>(acceptedOpps).keySet()));
    }

    public static void rerankAcceptedCandidates(Set<Id> jobPositionIds) {
        if (jobPositionIds == null || jobPositionIds.isEmpty()) return;

        Map<Id, Job_Position__c> jobsById = new Map<Id, Job_Position__c>([
            SELECT Id, Name, Open_Positions__c, Filled_Positions__c
            FROM Job_Position__c
            WHERE Id IN :jobPositionIds
        ]);

        List<Opportunity> acceptedOpps = [
            SELECT Id, Name, AccountId, OwnerId, Hiring_Manager__c,
                   Job_Position__c, StageName, Final_Applicant_Score__c,
                   Selection_Status__c, Contract_Status__c, ContractId, Contract_Signed__c
            FROM Opportunity
            WHERE Job_Position__c IN :jobPositionIds
              AND StageName = 'Accepted'
            ORDER BY Job_Position__c, Final_Applicant_Score__c DESC, CreatedDate ASC
        ];

        Map<Id, List<Opportunity>> oppsByJob = new Map<Id, List<Opportunity>>();
        for (Opportunity opp : acceptedOpps) {
            if (!oppsByJob.containsKey(opp.Job_Position__c)) {
                oppsByJob.put(opp.Job_Position__c, new List<Opportunity>());
            }
            oppsByJob.get(opp.Job_Position__c).add(opp);
        }

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Set<Id> oppIdsToSendContract = new Set<Id>();

        for (Id jobId : jobsById.keySet()) {
            Job_Position__c job = jobsById.get(jobId);
            Integer openPositions = toInt(job.Open_Positions__c);
            Integer filledPositions = toInt(job.Filled_Positions__c);
            Integer availableSlots = Math.max(openPositions - filledPositions, 0);

            List<Opportunity> candidates = oppsByJob.containsKey(jobId)
                ? oppsByJob.get(jobId) : new List<Opportunity>();

            Integer rankCounter = 0;

            for (Opportunity opp : candidates) {
                Boolean isTopCandidate = rankCounter < availableSlots;

                if (isTopCandidate) {
                    if (opp.Selection_Status__c == null
                        || opp.Selection_Status__c == 'Shortlisted'
                        || opp.Selection_Status__c == 'Not Selected'
                        || opp.Selection_Status__c == 'Expired') {

                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Selected for Contract';
                        if (opp.Contract_Status__c == null
                            || opp.Contract_Status__c == 'Expired'
                            || opp.Contract_Status__c == 'Not Sent') {
                            upd.Contract_Status__c = 'Not Sent';
                        }
                        oppsToUpdate.add(upd);
                        oppIdsToSendContract.add(opp.Id);
                    }
                    rankCounter++;
                } else {
                    if (opp.Selection_Status__c == 'Selected for Contract'
                        || opp.Selection_Status__c == 'Contract Sent') {
                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Shortlisted';
                        upd.Contract_Status__c = 'Expired';
                        oppsToUpdate.add(upd);
                    } else if (opp.Selection_Status__c == null
                        || opp.Selection_Status__c == 'Not Selected') {
                        Opportunity upd = new Opportunity(Id = opp.Id);
                        upd.Selection_Status__c = 'Shortlisted';
                        oppsToUpdate.add(upd);
                    }
                }
            }
        }

        if (!oppsToUpdate.isEmpty()) updateWithBypass(oppsToUpdate);
        if (!oppIdsToSendContract.isEmpty()) sendContractsForSelectedCandidates(oppIdsToSendContract);
        closeRemainingPendingCandidates(jobPositionIds);
        ensureHiringManagerShares(new Set<Id>(new Map<Id, Opportunity>(acceptedOpps).keySet()));
    }

    public static void sendContractsForSelectedCandidates(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return;

        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, OwnerId, Hiring_Manager__c,
                   Job_Position__c, Selection_Status__c, Contract_Status__c, ContractId
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND StageName = 'Accepted'
              AND Selection_Status__c = 'Selected for Contract'
              AND (ContractId = null OR Contract_Status__c = 'Expired')
        ];

        if (opps.isEmpty()) return;

        DateTime sentAt = System.now();
        DateTime deadline = sentAt.addHours(48);

        List<Contract> contractsToInsert = new List<Contract>();
        List<Id> oppOrder = new List<Id>();

        for (Opportunity opp : opps) {
            Contract c = new Contract();
            c.AccountId = opp.AccountId;
            c.OwnerId = opp.OwnerId;
            c.StartDate = Date.today();
            c.Status = 'Draft';
            c.Opportunity__c = opp.Id;
            c.Job_Position__c = opp.Job_Position__c;
            c.Deadline__c = deadline;
            contractsToInsert.add(c);
            oppOrder.add(opp.Id);
        }

        insert contractsToInsert;

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Integer i = 0; i < contractsToInsert.size(); i++) {
            Opportunity upd = new Opportunity(Id = oppOrder[i]);
            upd.ContractId = contractsToInsert[i].Id;
            upd.Contract_Status__c = 'Sent';
            upd.Contract_Sent_Date__c = sentAt;
            upd.Contract_Deadline__c = deadline;
            upd.Selection_Status__c = 'Contract Sent';
            oppsToUpdate.add(upd);
        }

        updateWithBypass(oppsToUpdate);
        sendSelectionEmails(opps, contractsToInsert, deadline);
        ensureHiringManagerShares(new Set<Id>(oppOrder));
    }

    public static void handleSignedContracts(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return;

        List<Opportunity> opps = [
            SELECT Id, Name, ContractId, Job_Position__c,
                   Contract_Signed__c, Hiring_Manager__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        if (opps.isEmpty()) return;

        Set<Id> jobIds = new Set<Id>();
        Set<Id> contractIds = new Set<Id>();
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        for (Opportunity opp : opps) {
            Opportunity upd = new Opportunity(Id = opp.Id);
            upd.Selection_Status__c = 'Signed';
            upd.Contract_Status__c = 'Signed';
            upd.Contract_Signed_Date__c = System.now();
            upd.StageName = 'Hired';
            upd.Final_Decision__c = 'Hired';
            upd.Decision_Date__c = Date.today();
            oppsToUpdate.add(upd);

            if (opp.Job_Position__c != null) jobIds.add(opp.Job_Position__c);
            if (opp.ContractId != null) contractIds.add(opp.ContractId);
        }

        if (!oppsToUpdate.isEmpty()) updateWithBypass(oppsToUpdate);

        if (!contractIds.isEmpty()) {
            List<Contract> contractsToUpdate = new List<Contract>();
            for (Id contractId : contractIds) {
                Contract c = new Contract(Id = contractId);
                c.Status = 'Activated';
                c.Candidate_Signed__c = true;
                c.CustomerSignedDate = Date.today();
                contractsToUpdate.add(c);
            }
            update contractsToUpdate;
        }

        recalculateFilledPositions(jobIds);
        closeRemainingPendingCandidates(jobIds);
        ensureHiringManagerShares(opportunityIds);
    }

    public static void expireUnsignedContracts() {
        List<Opportunity> expiredOpps = [
            SELECT Id, Name, Job_Position__c, ContractId,
                   Contract_Status__c, Contract_Signed__c, Contract_Deadline__c
            FROM Opportunity
            WHERE StageName = 'Accepted'
              AND Contract_Status__c = 'Sent'
              AND Contract_Signed__c = false
              AND Contract_Deadline__c != null
              AND Contract_Deadline__c <= :System.now()
        ];

        if (expiredOpps.isEmpty()) return;

        Set<Id> affectedJobIds = new Set<Id>();
        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        for (Opportunity opp : expiredOpps) {
            Opportunity upd = new Opportunity(Id = opp.Id);
            upd.Selection_Status__c = 'Expired';
            upd.Contract_Status__c = 'Expired';
            upd.StageName = 'Rejected';
            upd.Final_Decision__c = 'Rejected';
            upd.Decision_Date__c = Date.today();
            oppsToUpdate.add(upd);
            if (opp.Job_Position__c != null) affectedJobIds.add(opp.Job_Position__c);
        }

        updateWithBypass(oppsToUpdate);

        if (!affectedJobIds.isEmpty()) {
            recalculateFilledPositions(affectedJobIds);
            rerankAcceptedCandidates(affectedJobIds);
        }
    }

    public static void closeRemainingPendingCandidates(Set<Id> jobPositionIds) {
        if (jobPositionIds == null || jobPositionIds.isEmpty()) return;

        Map<Id, Job_Position__c> jobsById = new Map<Id, Job_Position__c>([
            SELECT Id, Open_Positions__c, Filled_Positions__c
            FROM Job_Position__c
            WHERE Id IN :jobPositionIds
        ]);

        Set<Id> fullJobIds = new Set<Id>();
        for (Job_Position__c job : jobsById.values()) {
            if (toInt(job.Filled_Positions__c) >= toInt(job.Open_Positions__c)) {
                fullJobIds.add(job.Id);
            }
        }

        if (fullJobIds.isEmpty()) return;

        List<Opportunity> oppsToClose = [
            SELECT Id, Selection_Status__c
            FROM Opportunity
            WHERE Job_Position__c IN :fullJobIds
              AND StageName = 'Accepted'
              AND Selection_Status__c IN ('Shortlisted', 'Selected for Contract', 'Contract Sent')
        ];

        if (oppsToClose.isEmpty()) return;

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity opp : oppsToClose) {
            Opportunity upd = new Opportunity(Id = opp.Id);
            if (opp.Selection_Status__c == 'Contract Sent') {
                upd.Selection_Status__c = 'Expired';
                upd.Contract_Status__c = 'Expired';
            } else {
                upd.Selection_Status__c = 'Not Selected';
            }
            upd.StageName = 'Rejected';
            upd.Final_Decision__c = 'Rejected';
            upd.Decision_Date__c = Date.today();
            oppsToUpdate.add(upd);
        }

        updateWithBypass(oppsToUpdate);
    }

    public static void ensureHiringManagerShares(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return;

        List<Opportunity> opps = [
            SELECT Id, OwnerId, Hiring_Manager__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
              AND Hiring_Manager__c != null
        ];

        if (opps.isEmpty()) return;

        Set<Id> oppIds = new Set<Id>();
        Set<Id> managerIds = new Set<Id>();

        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
            if (opp.Hiring_Manager__c != null && opp.Hiring_Manager__c != opp.OwnerId) {
                managerIds.add(opp.Hiring_Manager__c);
            }
        }

        if (oppIds.isEmpty() || managerIds.isEmpty()) return;

        Map<String, OpportunityShare> existingShares = new Map<String, OpportunityShare>();
        for (OpportunityShare sh : [
            SELECT Id, OpportunityId, UserOrGroupId, RowCause
            FROM OpportunityShare
            WHERE OpportunityId IN :oppIds
              AND UserOrGroupId IN :managerIds
        ]) {
            existingShares.put(sh.OpportunityId + '-' + sh.UserOrGroupId, sh);
        }

        List<OpportunityShare> sharesToInsert = new List<OpportunityShare>();
        for (Opportunity opp : opps) {
            if (opp.Hiring_Manager__c == null || opp.Hiring_Manager__c == opp.OwnerId) continue;
            String key = opp.Id + '-' + opp.Hiring_Manager__c;
            if (!existingShares.containsKey(key)) {
                OpportunityShare shareRow = new OpportunityShare();
                shareRow.OpportunityId = opp.Id;
                shareRow.UserOrGroupId = opp.Hiring_Manager__c;
                shareRow.OpportunityAccessLevel = 'Edit';
                shareRow.RowCause = Schema.OpportunityShare.RowCause.Manual;
                sharesToInsert.add(shareRow);
            }
        }

        if (!sharesToInsert.isEmpty()) {
            try {
                insert sharesToInsert;
            } catch (DmlException e) {
                System.debug('Sharing insert warning: ' + e.getMessage());
            }
        }
    }

    public static void sendSelectionEmails(List<Opportunity> opps, List<Contract> contracts, DateTime deadline) {
        if (opps == null || opps.isEmpty()) return;

        Set<Id> contractIds = new Set<Id>();
        for (Contract c : contracts) {
            if (c.Id != null) contractIds.add(c.Id);
        }

        Map<Id, Contract> contractsById = new Map<Id, Contract>([
            SELECT Id, ContractNumber, Opportunity__c
            FROM Contract
            WHERE Id IN :contractIds
        ]);

        Map<Id, Contract> contractByOppId = new Map<Id, Contract>();
        for (Contract c : contractsById.values()) {
            if (c.Opportunity__c != null) contractByOppId.put(c.Opportunity__c, c);
        }

        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : opps) {
            if (opp.AccountId != null) accountIds.add(opp.AccountId);
        }

        Map<Id, Account> accountsById = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountsById = new Map<Id, Account>([
                SELECT Id, Name, PersonEmail
                FROM Account
                WHERE Id IN :accountIds
            ]);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : opps) {
            Account acc = accountsById.get(opp.AccountId);
            if (acc == null || String.isBlank(acc.PersonEmail)) continue;

            Contract c = contractByOppId.get(opp.Id);
            String contractNumber = (c != null) ? c.ContractNumber : 'N/A';

            PageReference pdfPage = Page.ContractPDF;
            pdfPage.getParameters().put('contractId', c != null ? c.Id : '');
            pdfPage.getParameters().put('oppId', opp.Id);

            Blob pdfBlob;
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                System.debug('PDF generation failed: ' + e.getMessage());
                pdfBlob = Blob.valueOf('Contract document could not be generated.');
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('Contract_' + contractNumber + '.pdf');
            attachment.setBody(pdfBlob);
            attachment.setContentType('application/pdf');

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setOrgWideEmailAddressId(OWE_ID);
            mail.setToAddresses(new List<String>{ acc.PersonEmail });
            mail.setSubject('Your Employment Contract - ' + opp.Name);
            mail.setHtmlBody(
                TalentForceEmailTemplate.contractSent(
                    acc.Name, opp.Name, contractNumber,
                    deadline.format('MMMM dd, yyyy') + ' at ' + deadline.format('HH:mm')
                )
            );
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
            emails.add(mail);
        }

if (!emails.isEmpty()) {
    try {
        Messaging.sendEmail(emails);
    } catch (Exception e) {
        System.debug('sendSelectionEmails error: ' + e.getMessage());
    }
}    }

    private static Integer toInt(Decimal value) {
        return (value == null) ? 0 : Integer.valueOf(value.intValue());
    }

    private static void updateWithBypass(List<Opportunity> oppsToUpdate) {
        if (oppsToUpdate == null || oppsToUpdate.isEmpty()) return;
        bypassTrigger = true;
        try {
            update oppsToUpdate;
        } finally {
            bypassTrigger = false;
        }
    }

    public static void recalculateFilledPositions(Set<Id> jobPositionIds) {
        if (jobPositionIds == null || jobPositionIds.isEmpty()) return;

        Map<Id, Integer> hiredCountByJob = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Job_Position__c jobId, COUNT(Id) hiredCount
            FROM Opportunity
            WHERE Job_Position__c IN :jobPositionIds
              AND StageName = 'Hired'
            GROUP BY Job_Position__c
        ]) {
            hiredCountByJob.put((Id) ar.get('jobId'), (Integer) ar.get('hiredCount'));
        }

        List<Job_Position__c> jobsToUpdate = new List<Job_Position__c>();
        for (Id jobId : jobPositionIds) {
            Integer hiredCount = hiredCountByJob.containsKey(jobId)
                ? hiredCountByJob.get(jobId) : 0;
            jobsToUpdate.add(new Job_Position__c(Id = jobId, Filled_Positions__c = hiredCount));
        }

        if (!jobsToUpdate.isEmpty()) {
            bypassJobPositionTrigger = true;
            try {
                update jobsToUpdate;
            } finally {
                bypassJobPositionTrigger = false;
            }
        }
    }
}