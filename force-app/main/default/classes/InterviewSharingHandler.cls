/**
 * @description Handler class for InterviewSharingTrigger.
 *              Manages Apex Managed Sharing for Interview__c and Candidate__c
 *              when an interviewer is assigned, changed, or removed.
 *
 * @author      Hiba Balhirch
 * @version     1.2
 */
public with sharing class InterviewSharingHandler {
  /**
   * @description Handles after insert.
   * @param newInterviews Newly inserted interviews
   */
  public void onAfterInsert(List<Interview__c> newInterviews) {
    grantAccess(newInterviews);
  }

  /**
   * @description Handles after update.
   * @param newInterviews Updated interviews
   * @param oldMap Previous values
   */
  public void onAfterUpdate(
    List<Interview__c> newInterviews,
    Map<Id, Interview__c> oldMap
  ) {
    List<Interview__c> changed = new List<Interview__c>();
    List<Interview__c> oldChanged = new List<Interview__c>();

    for (Interview__c inv : newInterviews) {
      Interview__c oldInv = oldMap.get(inv.Id);
      if (oldInv != null && inv.Interviewer__c != oldInv.Interviewer__c) {
        changed.add(inv);
        oldChanged.add(oldInv);
      }
    }

    if (changed.isEmpty()) {
      return;
    }

    revokeAccess(oldChanged);
    grantAccess(changed);
  }

  /**
   * @description Handles after delete.
   * @param oldInterviews Deleted interviews
   */
  public void onAfterDelete(List<Interview__c> oldInterviews) {
    revokeAccess(oldInterviews);
  }

  /**
   * @description Grants Interview__Share and Candidate__Share access.
   * @param interviews Interviews to process
   */
  private void grantAccess(List<Interview__c> interviews) {
    Set<Id> interviewIds = new Set<Id>();

    for (Interview__c inv : interviews) {
      if (inv.Interviewer__c != null) {
        interviewIds.add(inv.Id);
      }
    }

    if (interviewIds.isEmpty()) {
      return;
    }

    if (!Schema.sObjectType.Interview__c.isAccessible()) {
      return;
    }

    Map<Id, Interview__c> interviewMap = new Map<Id, Interview__c>(
      [
        SELECT Id, Interviewer__c, Job_Application__r.Candidate__c
        FROM Interview__c
        WHERE Id IN :interviewIds
      ]
    );

    Set<Id> candidateIds = new Set<Id>();
    Set<Id> interviewerIds = new Set<Id>();

    for (Interview__c fetched : interviewMap.values()) {
      if (fetched.Interviewer__c != null) {
        interviewerIds.add(fetched.Interviewer__c);
      }
      if (
        fetched.Job_Application__r != null &&
        fetched.Job_Application__r.Candidate__c != null
      ) {
        candidateIds.add(fetched.Job_Application__r.Candidate__c);
      }
    }

    Map<String, Id> existingCandidateShareKeys = new Map<String, Id>();
    if (
      !candidateIds.isEmpty() &&
      !interviewerIds.isEmpty() &&
      Schema.sObjectType.Candidate__Share.isAccessible()
    ) {
      for (Candidate__Share shareRec : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Candidate__Share
        WHERE
          ParentId IN :candidateIds
          AND UserOrGroupId IN :interviewerIds
          AND RowCause = 'Manual'
      ]) {
        existingCandidateShareKeys.put(
          buildKey(shareRec.ParentId, shareRec.UserOrGroupId),
          shareRec.Id
        );
      }
    }

    Map<String, Id> existingInterviewShareKeys = new Map<String, Id>();
    if (
      !interviewIds.isEmpty() &&
      !interviewerIds.isEmpty() &&
      Schema.sObjectType.Interview__Share.isAccessible()
    ) {
      for (Interview__Share shareRec : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Interview__Share
        WHERE
          ParentId IN :interviewIds
          AND UserOrGroupId IN :interviewerIds
          AND RowCause = 'Manual'
      ]) {
        existingInterviewShareKeys.put(
          buildKey(shareRec.ParentId, shareRec.UserOrGroupId),
          shareRec.Id
        );
      }
    }

    List<Candidate__Share> candidateSharesToInsert = new List<Candidate__Share>();
    List<Interview__Share> interviewSharesToInsert = new List<Interview__Share>();

    for (Interview__c inv : interviews) {
      if (inv.Interviewer__c == null) {
        continue;
      }

      Interview__c fetched = interviewMap.get(inv.Id);
      if (fetched == null || fetched.Job_Application__r == null) {
        continue;
      }

      Id candidateId = fetched.Job_Application__r.Candidate__c;
      if (candidateId == null) {
        continue;
      }

      String candidateKey = buildKey(candidateId, inv.Interviewer__c);
      if (!existingCandidateShareKeys.containsKey(candidateKey)) {
        Candidate__Share candidateShare = new Candidate__Share();
        candidateShare.ParentId = candidateId;
        candidateShare.UserOrGroupId = inv.Interviewer__c;
        candidateShare.AccessLevel = 'Read';
        candidateShare.RowCause = Schema.Candidate__Share.RowCause.Manual;
        candidateSharesToInsert.add(candidateShare);
        existingCandidateShareKeys.put(candidateKey, null);
      }

      String interviewKey = buildKey(inv.Id, inv.Interviewer__c);
      if (!existingInterviewShareKeys.containsKey(interviewKey)) {
        Interview__Share interviewShare = new Interview__Share();
        interviewShare.ParentId = inv.Id;
        interviewShare.UserOrGroupId = inv.Interviewer__c;
        interviewShare.AccessLevel = 'Edit';
        interviewShare.RowCause = Schema.Interview__Share.RowCause.Manual;
        interviewSharesToInsert.add(interviewShare);
        existingInterviewShareKeys.put(interviewKey, null);
      }
    }

    if (
      !candidateSharesToInsert.isEmpty() &&
      Schema.sObjectType.Candidate__Share.isCreateable()
    ) {
      insert candidateSharesToInsert;
    }

    if (
      !interviewSharesToInsert.isEmpty() &&
      Schema.sObjectType.Interview__Share.isCreateable()
    ) {
      insert interviewSharesToInsert;
    }
  }

  /**
   * @description Revokes Interview__Share and Candidate__Share access.
   * @param oldInterviews Interviews with removed interviewer access
   */
  private void revokeAccess(List<Interview__c> oldInterviews) {
    if (oldInterviews == null || oldInterviews.isEmpty()) {
      return;
    }

    Set<Id> interviewIds = new Set<Id>();
    Set<Id> jobAppIds = new Set<Id>();
    Set<Id> interviewerIds = new Set<Id>();

    for (Interview__c inv : oldInterviews) {
      interviewIds.add(inv.Id);

      if (inv.Job_Application__c != null) {
        jobAppIds.add(inv.Job_Application__c);
      }

      if (inv.Interviewer__c != null) {
        interviewerIds.add(inv.Interviewer__c);
      }
    }

    Map<Id, Job_Application__c> jobAppMap = new Map<Id, Job_Application__c>();
    if (
      !jobAppIds.isEmpty() &&
      Schema.sObjectType.Job_Application__c.isAccessible()
    ) {
      jobAppMap = new Map<Id, Job_Application__c>(
        [
          SELECT Id, Candidate__c
          FROM Job_Application__c
          WHERE Id IN :jobAppIds
        ]
      );
    }

    Set<Id> candidateIds = new Set<Id>();
    for (Job_Application__c app : jobAppMap.values()) {
      if (app.Candidate__c != null) {
        candidateIds.add(app.Candidate__c);
      }
    }

    Map<String, List<Interview__Share>> interviewSharesByKey = new Map<String, List<Interview__Share>>();
    if (
      !interviewIds.isEmpty() &&
      !interviewerIds.isEmpty() &&
      Schema.sObjectType.Interview__Share.isAccessible()
    ) {
      for (Interview__Share shareRec : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Interview__Share
        WHERE
          ParentId IN :interviewIds
          AND UserOrGroupId IN :interviewerIds
          AND RowCause = 'Manual'
      ]) {
        String key = buildKey(shareRec.ParentId, shareRec.UserOrGroupId);
        if (!interviewSharesByKey.containsKey(key)) {
          interviewSharesByKey.put(key, new List<Interview__Share>());
        }
        interviewSharesByKey.get(key).add(shareRec);
      }
    }

    Map<String, Integer> remainingInterviewCounts = new Map<String, Integer>();
    if (!candidateIds.isEmpty() && !interviewerIds.isEmpty()) {
      for (Interview__c remaining : [
        SELECT Id, Interviewer__c, Job_Application__r.Candidate__c
        FROM Interview__c
        WHERE
          Job_Application__r.Candidate__c IN :candidateIds
          AND Interviewer__c IN :interviewerIds
          AND Id NOT IN :interviewIds
          AND Status__c != 'Cancelled'
          AND Status__c != 'No_Show'
      ]) {
        if (
          remaining.Job_Application__r == null ||
          remaining.Job_Application__r.Candidate__c == null
        ) {
          continue;
        }

        String key = buildKey(
          remaining.Job_Application__r.Candidate__c,
          remaining.Interviewer__c
        );
        Integer countValue = remainingInterviewCounts.containsKey(key)
          ? remainingInterviewCounts.get(key)
          : 0;
        remainingInterviewCounts.put(key, countValue + 1);
      }
    }

    Map<String, List<Candidate__Share>> candidateSharesByKey = new Map<String, List<Candidate__Share>>();
    if (
      !candidateIds.isEmpty() &&
      !interviewerIds.isEmpty() &&
      Schema.sObjectType.Candidate__Share.isAccessible()
    ) {
      for (Candidate__Share shareRec : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Candidate__Share
        WHERE
          ParentId IN :candidateIds
          AND UserOrGroupId IN :interviewerIds
          AND RowCause = 'Manual'
      ]) {
        String key = buildKey(shareRec.ParentId, shareRec.UserOrGroupId);
        if (!candidateSharesByKey.containsKey(key)) {
          candidateSharesByKey.put(key, new List<Candidate__Share>());
        }
        candidateSharesByKey.get(key).add(shareRec);
      }
    }

    List<Interview__Share> interviewSharesToDelete = new List<Interview__Share>();
    List<Candidate__Share> candidateSharesToDelete = new List<Candidate__Share>();

    for (Interview__c oldInv : oldInterviews) {
      if (oldInv.Interviewer__c == null) {
        continue;
      }

      String interviewKey = buildKey(oldInv.Id, oldInv.Interviewer__c);
      if (interviewSharesByKey.containsKey(interviewKey)) {
        interviewSharesToDelete.addAll(interviewSharesByKey.get(interviewKey));
      }

      Job_Application__c jobApp = jobAppMap.get(oldInv.Job_Application__c);
      if (jobApp == null || jobApp.Candidate__c == null) {
        continue;
      }

      String candidateKey = buildKey(
        jobApp.Candidate__c,
        oldInv.Interviewer__c
      );
      Integer remainingCount = remainingInterviewCounts.containsKey(
          candidateKey
        )
        ? remainingInterviewCounts.get(candidateKey)
        : 0;

      if (
        remainingCount == 0 && candidateSharesByKey.containsKey(candidateKey)
      ) {
        candidateSharesToDelete.addAll(candidateSharesByKey.get(candidateKey));
      }
    }

    if (
      !interviewSharesToDelete.isEmpty() &&
      Schema.sObjectType.Interview__Share.isDeletable()
    ) {
      delete interviewSharesToDelete;
    }

    if (
      !candidateSharesToDelete.isEmpty() &&
      Schema.sObjectType.Candidate__Share.isDeletable()
    ) {
      delete candidateSharesToDelete;
    }
  }

  /**
   * @description Builds a composite key from parent/user ids.
   * @param parentId Parent record id
   * @param userId User or group id
   * @return Composite key string
   */
  private static String buildKey(Id parentId, Id userId) {
    return String.valueOf(parentId) + '_' + String.valueOf(userId);
  }
}
