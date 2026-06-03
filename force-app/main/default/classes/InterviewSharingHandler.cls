/**
 * @description Handler class for InterviewSharingTrigger.
 * Grants and revokes record access for the user assigned as interviewer.
 */
public without sharing class InterviewSharingHandler {
  private static final String STATUS_CANCELLED = 'Cancelled';
  private static final String STATUS_NO_SHOW = 'No_Show';
  private static final String STATUS_SCHEDULING_EXPIRED = 'Scheduling_Expired';

  private static final String CANDIDATE_SHARE_OBJECT = 'Candidate__Share';
  private static final String JOB_POSITION_SHARE_OBJECT = 'Job_Position__Share';
  private static final String MANUAL_ROW_CAUSE = 'Manual';

  private static final Integer SOQL_SAFETY_LIMIT = 80;

  private static Map<String, Boolean> processedGrantKeys = new Map<String, Boolean>();
  private static Map<String, Boolean> processedRevokeKeys = new Map<String, Boolean>();

  public void onAfterInsert(List<Interview__c> newInterviews) {
    grantAccess(newInterviews);
  }

  public void onAfterUpdate(
    List<Interview__c> newInterviews,
    Map<Id, Interview__c> oldMap
  ) {
    List<Interview__c> interviewsToGrant = new List<Interview__c>();
    List<Interview__c> interviewsToRevoke = new List<Interview__c>();

    for (Interview__c newInterview : newInterviews) {
      Interview__c oldInterview = oldMap != null
        ? oldMap.get(newInterview.Id)
        : null;

      Boolean isClosed = isClosedStatus(newInterview.Status__c);
      Boolean interviewerChanged =
        oldInterview != null &&
        newInterview.Interviewer__c != oldInterview.Interviewer__c;

      if (
        oldInterview != null &&
        oldInterview.Interviewer__c != null &&
        (interviewerChanged || isClosed)
      ) {
        interviewsToRevoke.add(oldInterview);
      }

      if (!isClosed && newInterview.Interviewer__c != null) {
        interviewsToGrant.add(newInterview);
      }
    }

    revokeAccess(interviewsToRevoke);
    grantAccess(interviewsToGrant);
  }

  public void onAfterDelete(List<Interview__c> oldInterviews) {
    revokeAccess(oldInterviews);
  }

  private void grantAccess(List<Interview__c> interviews) {
    if (interviews == null || interviews.isEmpty()) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    Set<Id> interviewIds = new Set<Id>();

    for (Interview__c interviewRecord : interviews) {
      if (
        interviewRecord.Id == null ||
        interviewRecord.Interviewer__c == null
      ) {
        continue;
      }

      String grantKey = buildKey(
        interviewRecord.Id,
        interviewRecord.Interviewer__c
      );

      if (processedGrantKeys.containsKey(grantKey)) {
        continue;
      }

      processedGrantKeys.put(grantKey, true);
      interviewIds.add(interviewRecord.Id);
    }

    if (interviewIds.isEmpty()) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    Map<Id, Interview__c> fullInterviews = new Map<Id, Interview__c>(
      [
        SELECT
          Id,
          Interviewer__c,
          Job_Application__c,
          Job_Application__r.Candidate__c,
          Job_Application__r.Job_Position__c
        FROM Interview__c
        WHERE Id IN :interviewIds
        WITH SYSTEM_MODE
      ]
    );

    Set<Id> interviewerIds = new Set<Id>();
    Set<Id> candidateIds = new Set<Id>();
    Set<Id> jobPositionIds = new Set<Id>();

    for (Interview__c interviewRecord : fullInterviews.values()) {
      if (interviewRecord.Interviewer__c != null) {
        interviewerIds.add(interviewRecord.Interviewer__c);
      }

      if (interviewRecord.Job_Application__r != null) {
        if (interviewRecord.Job_Application__r.Candidate__c != null) {
          candidateIds.add(interviewRecord.Job_Application__r.Candidate__c);
        }

        if (interviewRecord.Job_Application__r.Job_Position__c != null) {
          jobPositionIds.add(
            interviewRecord.Job_Application__r.Job_Position__c
          );
        }
      }
    }

    if (interviewerIds.isEmpty()) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    Map<String, Id> existingInterviewShares = getExistingInterviewShareKeys(
      fullInterviews.keySet(),
      interviewerIds
    );

    Map<String, Id> existingCandidateShares = getExistingDynamicShareKeys(
      CANDIDATE_SHARE_OBJECT,
      candidateIds,
      interviewerIds
    );

    Map<String, Id> existingJobPositionShares = getExistingDynamicShareKeys(
      JOB_POSITION_SHARE_OBJECT,
      jobPositionIds,
      interviewerIds
    );

    List<Interview__Share> interviewSharesToInsert = new List<Interview__Share>();
    List<SObject> candidateSharesToInsert = new List<SObject>();
    List<SObject> jobPositionSharesToInsert = new List<SObject>();

    for (Interview__c interviewRecord : fullInterviews.values()) {
      if (interviewRecord.Interviewer__c == null) {
        continue;
      }

      String interviewKey = buildKey(
        interviewRecord.Id,
        interviewRecord.Interviewer__c
      );

      if (!existingInterviewShares.containsKey(interviewKey)) {
        Interview__Share interviewShare = new Interview__Share();
        interviewShare.ParentId = interviewRecord.Id;
        interviewShare.UserOrGroupId = interviewRecord.Interviewer__c;
        interviewShare.AccessLevel = 'Edit';
        interviewShare.RowCause = Schema.Interview__Share.RowCause.Manual;

        interviewSharesToInsert.add(interviewShare);
        existingInterviewShares.put(interviewKey, null);
      }

      if (interviewRecord.Job_Application__r != null) {
        if (interviewRecord.Job_Application__r.Candidate__c != null) {
          addDynamicShareIfMissing(
            CANDIDATE_SHARE_OBJECT,
            interviewRecord.Job_Application__r.Candidate__c,
            interviewRecord.Interviewer__c,
            'Read',
            existingCandidateShares,
            candidateSharesToInsert
          );
        }

        if (interviewRecord.Job_Application__r.Job_Position__c != null) {
          addDynamicShareIfMissing(
            JOB_POSITION_SHARE_OBJECT,
            interviewRecord.Job_Application__r.Job_Position__c,
            interviewRecord.Interviewer__c,
            'Read',
            existingJobPositionShares,
            jobPositionSharesToInsert
          );
        }
      }
    }

    if (!interviewSharesToInsert.isEmpty()) {
      logShareInsertErrors(
        'Interview__Share',
        Database.insert(interviewSharesToInsert, false, AccessLevel.SYSTEM_MODE)
      );
    }

    insertDynamicShares(CANDIDATE_SHARE_OBJECT, candidateSharesToInsert);
    insertDynamicShares(JOB_POSITION_SHARE_OBJECT, jobPositionSharesToInsert);
  }

  private void revokeAccess(List<Interview__c> oldInterviews) {
    if (oldInterviews == null || oldInterviews.isEmpty()) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    Set<Id> interviewIds = new Set<Id>();
    Set<Id> interviewerIds = new Set<Id>();
    Map<Id, Id> oldInterviewToInterviewer = new Map<Id, Id>();

    for (Interview__c interviewRecord : oldInterviews) {
      if (
        interviewRecord.Id == null ||
        interviewRecord.Interviewer__c == null
      ) {
        continue;
      }

      String revokeKey = buildKey(
        interviewRecord.Id,
        interviewRecord.Interviewer__c
      );

      if (processedRevokeKeys.containsKey(revokeKey)) {
        continue;
      }

      processedRevokeKeys.put(revokeKey, true);
      interviewIds.add(interviewRecord.Id);
      interviewerIds.add(interviewRecord.Interviewer__c);
      oldInterviewToInterviewer.put(
        interviewRecord.Id,
        interviewRecord.Interviewer__c
      );
    }

    if (interviewIds.isEmpty() || interviewerIds.isEmpty()) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    List<Interview__c> fullOldInterviews = [
      SELECT
        Id,
        Interviewer__c,
        Job_Application__c,
        Job_Application__r.Candidate__c,
        Job_Application__r.Job_Position__c
      FROM Interview__c
      WHERE Id IN :interviewIds
      WITH SYSTEM_MODE
    ];

    Map<String, Id> candidateUserPairs = new Map<String, Id>();
    Map<String, Id> jobPositionUserPairs = new Map<String, Id>();

    for (Interview__c interviewRecord : fullOldInterviews) {
      Id originalInterviewerId = oldInterviewToInterviewer.get(
        interviewRecord.Id
      );

      if (originalInterviewerId == null) {
        continue;
      }

      if (interviewRecord.Job_Application__r != null) {
        Id candidateId = interviewRecord.Job_Application__r.Candidate__c;
        Id jobPositionId = interviewRecord.Job_Application__r.Job_Position__c;

        if (candidateId != null) {
          candidateUserPairs.put(
            buildKey(candidateId, originalInterviewerId),
            candidateId
          );
        }

        if (jobPositionId != null) {
          jobPositionUserPairs.put(
            buildKey(jobPositionId, originalInterviewerId),
            jobPositionId
          );
        }
      }
    }

    List<Interview__Share> interviewSharesToDelete = getInterviewSharesToDelete(
      interviewIds,
      interviewerIds
    );

    if (!interviewSharesToDelete.isEmpty()) {
      logShareDeleteErrors(
        'Interview__Share',
        Database.delete(interviewSharesToDelete, false, AccessLevel.SYSTEM_MODE)
      );
    }

    deleteDynamicShares(
      CANDIDATE_SHARE_OBJECT,
      sharesToDeleteFromPairs(
        CANDIDATE_SHARE_OBJECT,
        candidateUserPairs,
        new Set<String>()
      )
    );

    deleteDynamicShares(
      JOB_POSITION_SHARE_OBJECT,
      sharesToDeleteFromPairs(
        JOB_POSITION_SHARE_OBJECT,
        jobPositionUserPairs,
        new Set<String>()
      )
    );
  }

  private List<SObject> sharesToDeleteFromPairs(
    String shareObjectName,
    Map<String, Id> pairMap,
    Set<String> stillNeededPairs
  ) {
    Set<Id> parentIds = new Set<Id>();
    Set<Id> userIds = new Set<Id>();

    for (String pairKey : pairMap.keySet()) {
      if (stillNeededPairs.contains(pairKey)) {
        continue;
      }

      List<String> parts = pairKey.split('_');

      if (parts.size() == 2) {
        parentIds.add((Id) parts[0]);
        userIds.add((Id) parts[1]);
      }
    }

    return getDynamicSharesToDelete(shareObjectName, parentIds, userIds);
  }

  private void addDynamicShareIfMissing(
    String shareObjectName,
    Id parentId,
    Id userId,
    String accessLevel,
    Map<String, Id> existingKeys,
    List<SObject> recordsToInsert
  ) {
    if (
      parentId == null ||
      userId == null ||
      !shareObjectExists(shareObjectName)
    ) {
      return;
    }

    String key = buildKey(parentId, userId);

    if (existingKeys.containsKey(key)) {
      return;
    }

    SObject shareRecord = Schema.getGlobalDescribe()
      .get(shareObjectName)
      .newSObject();
    shareRecord.put('ParentId', parentId);
    shareRecord.put('UserOrGroupId', userId);
    shareRecord.put('AccessLevel', accessLevel);
    shareRecord.put('RowCause', MANUAL_ROW_CAUSE);

    recordsToInsert.add(shareRecord);
    existingKeys.put(key, null);
  }

  private void insertDynamicShares(
    String shareObjectName,
    List<SObject> shares
  ) {
    if (
      shares == null ||
      shares.isEmpty() ||
      !shareObjectExists(shareObjectName)
    ) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    logShareInsertErrors(
      shareObjectName,
      Database.insert(shares, false, AccessLevel.SYSTEM_MODE)
    );
  }

  private void deleteDynamicShares(
    String shareObjectName,
    List<SObject> shares
  ) {
    if (
      shares == null ||
      shares.isEmpty() ||
      !shareObjectExists(shareObjectName)
    ) {
      return;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return;
    }

    logShareDeleteErrors(
      shareObjectName,
      Database.delete(shares, false, AccessLevel.SYSTEM_MODE)
    );
  }

  private List<Interview__Share> getInterviewSharesToDelete(
    Set<Id> parentIds,
    Set<Id> userIds
  ) {
    if (parentIds.isEmpty() || userIds.isEmpty()) {
      return new List<Interview__Share>();
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return new List<Interview__Share>();
    }

    return [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId IN :parentIds
        AND UserOrGroupId IN :userIds
        AND RowCause = 'Manual'
      WITH SYSTEM_MODE
    ];
  }

  private Map<String, Id> getExistingInterviewShareKeys(
    Set<Id> parentIds,
    Set<Id> userIds
  ) {
    Map<String, Id> result = new Map<String, Id>();

    if (parentIds.isEmpty() || userIds.isEmpty()) {
      return result;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return result;
    }

    for (Interview__Share shareRecord : [
      SELECT Id, ParentId, UserOrGroupId
      FROM Interview__Share
      WHERE
        ParentId IN :parentIds
        AND UserOrGroupId IN :userIds
        AND RowCause = 'Manual'
      WITH SYSTEM_MODE
    ]) {
      result.put(
        buildKey(shareRecord.ParentId, shareRecord.UserOrGroupId),
        shareRecord.Id
      );
    }

    return result;
  }

  private Map<String, Id> getExistingDynamicShareKeys(
    String shareObjectName,
    Set<Id> parentIds,
    Set<Id> userIds
  ) {
    Map<String, Id> result = new Map<String, Id>();

    if (
      parentIds.isEmpty() ||
      userIds.isEmpty() ||
      !shareObjectExists(shareObjectName)
    ) {
      return result;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return result;
    }

    if (shareObjectName == CANDIDATE_SHARE_OBJECT) {
      for (Candidate__Share shareRecord : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Candidate__Share
        WHERE
          ParentId IN :parentIds
          AND UserOrGroupId IN :userIds
          AND RowCause = 'Manual'
        WITH SYSTEM_MODE
      ]) {
        result.put(
          buildKey(shareRecord.ParentId, shareRecord.UserOrGroupId),
          shareRecord.Id
        );
      }
    } else if (shareObjectName == JOB_POSITION_SHARE_OBJECT) {
      for (Job_Position__Share shareRecord : [
        SELECT Id, ParentId, UserOrGroupId
        FROM Job_Position__Share
        WHERE
          ParentId IN :parentIds
          AND UserOrGroupId IN :userIds
          AND RowCause = 'Manual'
        WITH SYSTEM_MODE
      ]) {
        result.put(
          buildKey(shareRecord.ParentId, shareRecord.UserOrGroupId),
          shareRecord.Id
        );
      }
    }

    return result;
  }

  private List<SObject> getDynamicSharesToDelete(
    String shareObjectName,
    Set<Id> parentIds,
    Set<Id> userIds
  ) {
    List<SObject> result = new List<SObject>();

    if (
      parentIds.isEmpty() ||
      userIds.isEmpty() ||
      !shareObjectExists(shareObjectName)
    ) {
      return result;
    }

    if (Limits.getQueries() >= SOQL_SAFETY_LIMIT) {
      return result;
    }

    if (shareObjectName == CANDIDATE_SHARE_OBJECT) {
      for (Candidate__Share shareRecord : [
        SELECT Id
        FROM Candidate__Share
        WHERE
          ParentId IN :parentIds
          AND UserOrGroupId IN :userIds
          AND RowCause = 'Manual'
        WITH SYSTEM_MODE
      ]) {
        result.add(shareRecord);
      }
    } else if (shareObjectName == JOB_POSITION_SHARE_OBJECT) {
      for (Job_Position__Share shareRecord : [
        SELECT Id
        FROM Job_Position__Share
        WHERE
          ParentId IN :parentIds
          AND UserOrGroupId IN :userIds
          AND RowCause = 'Manual'
        WITH SYSTEM_MODE
      ]) {
        result.add(shareRecord);
      }
    }

    return result;
  }

  private Boolean shareObjectExists(String shareObjectName) {
    return Schema.getGlobalDescribe().containsKey(shareObjectName);
  }

  private static Boolean isClosedStatus(String statusValue) {
    return getClosedStatuses().contains(statusValue);
  }

  private static Set<String> getClosedStatuses() {
    return new Set<String>{
      STATUS_CANCELLED,
      STATUS_NO_SHOW,
      STATUS_SCHEDULING_EXPIRED
    };
  }

  private void logShareInsertErrors(
    String shareObjectName,
    List<Database.SaveResult> results
  ) {
    for (Database.SaveResult result : results) {
      if (!result.isSuccess()) {
        for (Database.Error error : result.getErrors()) {
          System.debug(
            LoggingLevel.WARN,
            shareObjectName +
              ' insert failed. Status=' +
              error.getStatusCode() +
              ', Message=' +
              error.getMessage()
          );
        }
      }
    }
  }

  private void logShareDeleteErrors(
    String shareObjectName,
    List<Database.DeleteResult> results
  ) {
    for (Database.DeleteResult result : results) {
      if (!result.isSuccess()) {
        for (Database.Error error : result.getErrors()) {
          System.debug(
            LoggingLevel.WARN,
            shareObjectName +
              ' delete failed. Status=' +
              error.getStatusCode() +
              ', Message=' +
              error.getMessage()
          );
        }
      }
    }
  }

  private static String buildKey(Id parentId, Id userId) {
    return String.valueOf(parentId) + '_' + String.valueOf(userId);
  }
}
