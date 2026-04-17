/**
 * @description Handler class for InterviewSharingTrigger.
 *              Manages Apex Managed Sharing for Interview__c and Candidate__c
 *              objects when an Interviewer is assigned, changed, or removed.
 *
 *              Sharing rules:
 *              - Interviewer gets Edit access to their Interview__c record
 *              - Interviewer gets Read access to the related Candidate__c record
 *              - Access is revoked when interviewer has no remaining active
 *                interviews with the same candidate
 *
 * @author      Hiba Balhirch
 * @version     1.0
 */
public with sharing class InterviewSharingHandler {

    // -----------------------------------------------
    // AFTER INSERT
    // -----------------------------------------------

    /**
     * @description Handles after insert event.
     *              Creates Candidate__Share and Interview__Share
     *              for the assigned Interviewer.
     * @param newInterviews List of newly created Interview__c records
     */
    public void onAfterInsert(List<Interview__c> newInterviews) {
        grantAccess(newInterviews);
    }

    // -----------------------------------------------
    // AFTER UPDATE
    // -----------------------------------------------

    /**
     * @description Handles after update event.
     *              If Interviewer changed: revokes old interviewer's access
     *              (if no other active interviews with same candidate exist)
     *              and grants access to the new interviewer.
     * @param newInterviews List of updated Interview__c records (new values)
     * @param oldMap Map of Interview__c records before update (old values)
     */
    public void onAfterUpdate(List<Interview__c> newInterviews, Map<Id, Interview__c> oldMap) {
        List<Interview__c> changed    = new List<Interview__c>();
        List<Interview__c> oldChanged = new List<Interview__c>();

        for (Interview__c inv : newInterviews) {
            Interview__c oldInv = oldMap.get(inv.Id);
            if (inv.Interviewer__c != oldInv.Interviewer__c) {
                changed.add(inv);
                oldChanged.add(oldInv);
            }
        }

        if (changed.isEmpty()) return;

        revokeAccess(oldChanged);
        grantAccess(changed);
    }

    // -----------------------------------------------
    // AFTER DELETE
    // -----------------------------------------------

    /**
     * @description Handles after delete event.
     *              Revokes Interviewer's access to Interview__c record.
     *              Revokes Candidate__c access only if interviewer has
     *              no other active interviews with the same candidate.
     * @param oldInterviews List of deleted Interview__c records
     */
    public void onAfterDelete(List<Interview__c> oldInterviews) {
        revokeAccess(oldInterviews);
    }

    // -----------------------------------------------
    // PRIVATE: GRANT ACCESS
    // -----------------------------------------------

    /**
     * @description Grants Edit access to Interview__c and Read access to Candidate__c
     *              for the assigned Interviewer.
     *              Skips if share already exists to avoid duplicates.
     * @param interviews List of Interview__c records to process
     */
    private void grantAccess(List<Interview__c> interviews) {

        Set<Id> interviewIds = new Set<Id>();
        for (Interview__c inv : interviews) {
            if (inv.Interviewer__c != null) {
                interviewIds.add(inv.Id);
            }
        }
        if (interviewIds.isEmpty()) return;

        // Query interviews with related Candidate ID
        Map<Id, Interview__c> interviewMap = new Map<Id, Interview__c>([
            SELECT Id,
                   Interviewer__c,
                   Job_Application__r.Candidate__c
            FROM Interview__c
            WHERE Id IN :interviewIds
        ]);

        List<Candidate__Share> candidateSharesToInsert = new List<Candidate__Share>();
        List<Interview__Share> interviewSharesToInsert = new List<Interview__Share>();

        Set<String> processedCandidateShares = new Set<String>();
        Set<String> processedInterviewShares = new Set<String>();

        for (Interview__c inv : interviews) {
            if (inv.Interviewer__c == null) continue;

            Interview__c fetched = interviewMap.get(inv.Id);
            if (fetched == null) continue;

            Id candidateId = fetched.Job_Application__r.Candidate__c;
            if (candidateId == null) continue;

            // --- Candidate__Share ---
            String candidateKey = candidateId + '_' + inv.Interviewer__c;
            if (!processedCandidateShares.contains(candidateKey)) {
                processedCandidateShares.add(candidateKey);

                List<Candidate__Share> existing = [
                    SELECT Id FROM Candidate__Share
                    WHERE ParentId      = :candidateId
                    AND UserOrGroupId   = :inv.Interviewer__c
                    AND RowCause        = 'Manual'
                ];

                if (existing.isEmpty()) {
                    Candidate__Share cs = new Candidate__Share();
                    cs.ParentId      = candidateId;
                    cs.UserOrGroupId = inv.Interviewer__c;
                    cs.AccessLevel   = 'Read';
                    cs.RowCause      = 'Manual';
                    candidateSharesToInsert.add(cs);
                }
            }

            // --- Interview__Share ---
            String interviewKey = inv.Id + '_' + inv.Interviewer__c;
            if (!processedInterviewShares.contains(interviewKey)) {
                processedInterviewShares.add(interviewKey);

                List<Interview__Share> existing = [
                    SELECT Id FROM Interview__Share
                    WHERE ParentId      = :inv.Id
                    AND UserOrGroupId   = :inv.Interviewer__c
                    AND RowCause        = 'Manual'
                ];

                if (existing.isEmpty()) {
                    Interview__Share is = new Interview__Share();
                    is.ParentId      = inv.Id;
                    is.UserOrGroupId = inv.Interviewer__c;
                    is.AccessLevel   = 'Edit';
                    is.RowCause      = 'Manual';
                    interviewSharesToInsert.add(is);
                }
            }
        }

        if (!candidateSharesToInsert.isEmpty()) insert candidateSharesToInsert;
        if (!interviewSharesToInsert.isEmpty()) insert interviewSharesToInsert;
    }

    // -----------------------------------------------
    // PRIVATE: REVOKE ACCESS
    // -----------------------------------------------

    /**
     * @description Revokes Interviewer access when they are removed from an interview.
     *
     *              Interview__Share → always deleted for the specific interview record.
     *
     *              Candidate__Share → deleted ONLY if the interviewer has no other
     *              active interviews (not Cancelled or No_Show) with the same candidate.
     *
     *              NOTE: On delete, Interview__c records are already gone so we query
     *              Job_Application__c directly using the ID from Trigger.old.
     *
     * @param oldInterviews List of Interview__c records with old/removed interviewer values
     */
    private void revokeAccess(List<Interview__c> oldInterviews) {

        Set<Id> interviewIds = new Set<Id>();
        Set<Id> jobAppIds    = new Set<Id>();

        for (Interview__c inv : oldInterviews) {
            interviewIds.add(inv.Id);
            if (inv.Job_Application__c != null) {
                jobAppIds.add(inv.Job_Application__c);
            }
        }

        // Query Job Applications to get Candidate IDs
        // We query Job_Application__c instead of Interview__c
        // because on delete the Interview records no longer exist
        Map<Id, Job_Application__c> jobAppMap = new Map<Id, Job_Application__c>([
            SELECT Id, Candidate__c
            FROM Job_Application__c
            WHERE Id IN :jobAppIds
        ]);

        List<Candidate__Share> candidateSharesToDelete = new List<Candidate__Share>();
        List<Interview__Share> interviewSharesToDelete = new List<Interview__Share>();

        for (Interview__c oldInv : oldInterviews) {
            if (oldInv.Interviewer__c == null) continue;

            Job_Application__c jobApp = jobAppMap.get(oldInv.Job_Application__c);
            if (jobApp == null) continue;

            Id candidateId = jobApp.Candidate__c;
            if (candidateId == null) continue;

            // --- Always delete Interview__Share for this specific interview ---
            List<Interview__Share> interviewShares = [
                SELECT Id FROM Interview__Share
                WHERE ParentId      = :oldInv.Id
                AND UserOrGroupId   = :oldInv.Interviewer__c
                AND RowCause        = 'Manual'
            ];
            interviewSharesToDelete.addAll(interviewShares);

            // --- Delete Candidate__Share only if no other active interviews remain ---
            List<Interview__c> remainingInterviews = [
                SELECT Id FROM Interview__c
                WHERE Job_Application__r.Candidate__c  = :candidateId
                AND Interviewer__c                      = :oldInv.Interviewer__c
                AND Id NOT IN                           :interviewIds
                AND Status__c                          != 'Cancelled'
                AND Status__c                          != 'No_Show'
            ];

            if (remainingInterviews.isEmpty()) {
                List<Candidate__Share> candidateShares = [
                    SELECT Id FROM Candidate__Share
                    WHERE ParentId      = :candidateId
                    AND UserOrGroupId   = :oldInv.Interviewer__c
                    AND RowCause        = 'Manual'
                ];
                candidateSharesToDelete.addAll(candidateShares);
            }
        }

        if (!interviewSharesToDelete.isEmpty()) delete interviewSharesToDelete;
        if (!candidateSharesToDelete.isEmpty()) delete candidateSharesToDelete;
    }
}