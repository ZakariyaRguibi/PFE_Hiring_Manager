public with sharing class RecruitmentOpportunityTriggerHandler {
    public static void handle(
        Map<Id, Opportunity> oldMap,
        Map<Id, Opportunity> newMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        Set<Id> signedOpportunityIds = new Set<Id>();
        Set<Id> opportunitiesToShare = new Set<Id>();
        Set<Id> shortlistedOppIds = new Set<Id>();
        Set<Id> hiredOppIds = new Set<Id>();
        Map<Id, String> rejectedOppIds = new Map<Id, String>();

        for (Opportunity opp : newMap.values()) {
            Opportunity oldOpp = (oldMap == null) ? null : oldMap.get(opp.Id);
            if (isUpdate && oldOpp != null) {
                if (opp.Contract_Signed__c == true && oldOpp.Contract_Signed__c != true) {
                    signedOpportunityIds.add(opp.Id);
                }
                if (opp.Selection_Status__c == 'Shortlisted'
                    && oldOpp.Selection_Status__c != 'Shortlisted') {
                    shortlistedOppIds.add(opp.Id);
                }
                if (opp.StageName == 'Hired' && oldOpp.StageName != 'Hired') {
                    hiredOppIds.add(opp.Id);
                }
                // ── Rejected ──
                if (opp.StageName == 'Rejected' && oldOpp.StageName != 'Rejected') {
                    String reason = 'Standard';
                    if (opp.Contract_Status__c == 'Expired') {
                        reason = 'Expired Contract';
                    }
                    rejectedOppIds.put(opp.Id, reason);
                }
                // ── Withdrawn ──
                if (opp.StageName == 'Withdrawn' && oldOpp.StageName != 'Withdrawn') {
                    rejectedOppIds.put(opp.Id, 'Withdrawn');
                }
            }
            if (opp.Hiring_Manager__c != null) {
                opportunitiesToShare.add(opp.Id);
            }
        }

        if (!signedOpportunityIds.isEmpty()) {
            RecruitmentHiringService.handleSignedContracts(signedOpportunityIds);
        }
        if (!opportunitiesToShare.isEmpty()) {
            RecruitmentHiringService.ensureHiringManagerShares(opportunitiesToShare);
        }
        if (!shortlistedOppIds.isEmpty()) {
            RecruitmentEmailService.sendShortlistedEmails(shortlistedOppIds);
        }
        if (!hiredOppIds.isEmpty()) {
            RecruitmentEmailService.sendHiredEmails(hiredOppIds);
        }
        if (!rejectedOppIds.isEmpty()) {
            RecruitmentEmailService.sendRejectedEmails(rejectedOppIds);
        }
    }
}