/**
 * @description Handles validation logic for Availability_Slot__c triggers.
 * Prevents overlapping availability slots for the same interviewer.
 */
public inherited sharing class AvailabilitySlotTriggerHandler {
  /**
   * @description Entry point called by the trigger. Delegates to overlap validation.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  public static void handle(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    validateNoOverlappingSlots(newList, oldMap);
  }

  /**
   * @description Collects slots whose interviewer or time window changed.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   * @return list of slots that require overlap checking
   */
  private static List<Availability_Slot__c> collectChanged(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    List<Availability_Slot__c> toCheck = new List<Availability_Slot__c>();
    for (Availability_Slot__c slot : newList) {
      if (
        slot.Interviewer__c == null ||
        slot.Start_DateTime__c == null ||
        slot.End_DateTime__c == null
      ) {
        continue;
      }
      if (oldMap != null) {
        Availability_Slot__c old = oldMap.get(slot.Id);
        if (
          old.Start_DateTime__c == slot.Start_DateTime__c &&
          old.End_DateTime__c == slot.End_DateTime__c &&
          old.Interviewer__c == slot.Interviewer__c
        ) {
          continue;
        }
      }
      toCheck.add(slot);
    }
    return toCheck;
  }

  /**
   * @description Queries existing slots that fall within the bounding box of the candidates.
   * Uses min/max datetime across all candidates to minimize result set.
   * @param toCheck slots to check
   * @return existing slots potentially overlapping with candidates
   */
  private static List<Availability_Slot__c> queryOverlappingCandidates(
    List<Availability_Slot__c> toCheck
  ) {
    Set<Id> interviewerIds = new Set<Id>();
    Datetime minStart = null;
    Datetime maxEnd = null;
    for (Availability_Slot__c slot : toCheck) {
      interviewerIds.add(slot.Interviewer__c);
      if (minStart == null || slot.Start_DateTime__c < minStart) {
        minStart = slot.Start_DateTime__c;
      }
      if (maxEnd == null || slot.End_DateTime__c > maxEnd) {
        maxEnd = slot.End_DateTime__c;
      }
    }
    return [
      SELECT Id, Interviewer__c, Start_DateTime__c, End_DateTime__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Start_DateTime__c < :maxEnd
        AND End_DateTime__c > :minStart
      WITH SYSTEM_MODE
    ];
  }

  /**
   * @description No overlapping slots for the same interviewer.
   * Two slots overlap if one starts before the other ends.
   * @param newList records being inserted or updated
   * @param oldMap previous record state (null on insert)
   */
  private static void validateNoOverlappingSlots(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    List<Availability_Slot__c> toCheck = collectChanged(newList, oldMap);
    if (toCheck.isEmpty()) {
      return;
    }

    List<Availability_Slot__c> existing = queryOverlappingCandidates(toCheck);

    Map<Id, List<Availability_Slot__c>> byInterviewer = new Map<Id, List<Availability_Slot__c>>();
    for (Availability_Slot__c ex : existing) {
      if (!byInterviewer.containsKey(ex.Interviewer__c)) {
        byInterviewer.put(ex.Interviewer__c, new List<Availability_Slot__c>());
      }
      byInterviewer.get(ex.Interviewer__c).add(ex);
    }

    for (Availability_Slot__c slot : toCheck) {
      List<Availability_Slot__c> candidates = byInterviewer.get(
        slot.Interviewer__c
      );
      if (candidates == null) {
        continue;
      }
      for (Availability_Slot__c ex : candidates) {
        if (ex.Id == slot.Id) {
          continue;
        }
        if (
          ex.Start_DateTime__c < slot.End_DateTime__c &&
          ex.End_DateTime__c > slot.Start_DateTime__c
        ) {
          slot.Start_DateTime__c.addError(
            'This interviewer already has an availability slot that overlaps with this time window.'
          );
          break;
        }
      }
    }
  }
}
