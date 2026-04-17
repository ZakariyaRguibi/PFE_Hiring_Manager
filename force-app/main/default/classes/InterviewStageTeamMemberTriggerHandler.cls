/**
 * @description Handles validation logic for Interview_Stage_Team_Member__c triggers.
 * Enforces that each interviewer appears at most once per Interview_Stage__c.
 */
public inherited sharing class InterviewStageTeamMemberTriggerHandler {
  /**
   * @description Entry point called by the trigger. Delegates to interviewer uniqueness validation.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  public static void handle(
    List<Interview_Stage_Team_Member__c> newList,
    Map<Id, Interview_Stage_Team_Member__c> oldMap
  ) {
    validateUniqueInterviewerPerStage(newList, oldMap);
  }

  /**
   * @description An interviewer can only appear once per Interview Stage.
   * Null Interviewer__c is allowed (pool member not yet assigned).
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  private static void validateUniqueInterviewerPerStage(
    List<Interview_Stage_Team_Member__c> newList,
    Map<Id, Interview_Stage_Team_Member__c> oldMap
  ) {
    List<Interview_Stage_Team_Member__c> toCheck = collectChanged(
      newList,
      oldMap
    );
    if (toCheck.isEmpty()) {
      return;
    }

    Set<String> existingKeys = queryExistingKeys(toCheck);
    Set<String> batchKeys = new Set<String>();

    for (Interview_Stage_Team_Member__c member : toCheck) {
      if (member.Interviewer__c == null) {
        continue;
      }
      String key = member.Interview_Stage__c + '_' + member.Interviewer__c;
      if (existingKeys.contains(key) || batchKeys.contains(key)) {
        member.Interviewer__c.addError(
          'This interviewer is already a member of this Interview Stage.'
        );
      } else {
        batchKeys.add(key);
      }
    }
  }

  /**
   * @description Filters members where Interview_Stage__c or Interviewer__c changed.
   * Records with a null Interviewer__c are skipped (pool placeholders allowed).
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   * @return members that require uniqueness checking
   */
  private static List<Interview_Stage_Team_Member__c> collectChanged(
    List<Interview_Stage_Team_Member__c> newList,
    Map<Id, Interview_Stage_Team_Member__c> oldMap
  ) {
    List<Interview_Stage_Team_Member__c> result = new List<Interview_Stage_Team_Member__c>();
    for (Interview_Stage_Team_Member__c member : newList) {
      if (member.Interview_Stage__c == null || member.Interviewer__c == null) {
        continue;
      }
      if (oldMap != null) {
        Interview_Stage_Team_Member__c old = oldMap.get(member.Id);
        if (
          old.Interview_Stage__c == member.Interview_Stage__c &&
          old.Interviewer__c == member.Interviewer__c
        ) {
          continue;
        }
      }
      result.add(member);
    }
    return result;
  }

  /**
   * @description Queries existing members for the affected stages and interviewers.
   * @param toCheck members to check
   * @return set of composite keys in the form stageId_interviewerId
   */
  private static Set<String> queryExistingKeys(
    List<Interview_Stage_Team_Member__c> toCheck
  ) {
    Set<Id> stageIds = new Set<Id>();
    Set<Id> interviewerIds = new Set<Id>();
    for (Interview_Stage_Team_Member__c member : toCheck) {
      stageIds.add(member.Interview_Stage__c);
      interviewerIds.add(member.Interviewer__c);
    }

    List<Interview_Stage_Team_Member__c> existing = [
      SELECT Id, Interview_Stage__c, Interviewer__c
      FROM Interview_Stage_Team_Member__c
      WHERE
        Interview_Stage__c IN :stageIds
        AND Interviewer__c IN :interviewerIds
      WITH SYSTEM_MODE
    ];

    Set<String> keys = new Set<String>();
    for (Interview_Stage_Team_Member__c ex : existing) {
      keys.add(ex.Interview_Stage__c + '_' + ex.Interviewer__c);
    }
    return keys;
  }
}
