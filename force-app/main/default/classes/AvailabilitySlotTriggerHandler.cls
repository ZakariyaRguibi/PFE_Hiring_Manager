/**
 * @description Handles validation and retry orchestration for Availability_Slot__c triggers.
 */
public inherited sharing class AvailabilitySlotTriggerHandler {
  /**
   * @description Prevents scheduling retry logic from running when availability records are created internally.
   */
  public static Boolean skipSchedulingRetry = false;

  /**
   * @description Runs before-save validation for availability slots.
   * @param newList New availability slot records.
   * @param oldMap Previous availability slot values, null on insert.
   */
  public static void handleBeforeSave(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    validateNoOverlappingSlots(newList, oldMap);
  }

  /**
   * @description Runs after-save scheduling retry logic for waiting job applications.
   * @param newList New availability slot records.
   * @param oldMap Previous availability slot values, null on insert.
   */
  public static void handleAfterSave(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    if (skipSchedulingRetry == true) {
      return;
    }

    JobApplicationInterviewSchedulingService.handleAvailabilityAfterSave(
      newList,
      oldMap
    );
  }

  /**
   * @description Backward-compatible entry point used by older trigger versions.
   * @param newList New availability slot records.
   * @param oldMap Previous availability slot values, null on insert.
   */
  public static void handle(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    handleBeforeSave(newList, oldMap);
  }

  /**
   * @description Collects records whose interviewer or time window changed.
   * @param newList New availability slot records.
   * @param oldMap Previous availability slot values, null on insert.
   * @return Availability slots that require overlap validation.
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
   * @description Queries active availability slots that may overlap with the candidate records.
   * @param toCheck Availability slots being validated.
   * @return Existing active slots that fall inside the global time range being checked.
   */
  private static List<Availability_Slot__c> queryOverlappingCandidates(
    List<Availability_Slot__c> toCheck
  ) {
    Set<Id> interviewerIds = new Set<Id>();
    Datetime minStart;
    Datetime maxEnd;

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
      SELECT
        Id,
        Interviewer__c,
        Start_DateTime__c,
        End_DateTime__c,
        Is_Recurring__c,
        Is_Blocked__c,
        Is_Booked__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Deactivated_Date__c = NULL
        AND Start_DateTime__c < :maxEnd
        AND End_DateTime__c > :minStart
      WITH SYSTEM_MODE
    ];
  }

  /**
   * @description Validates that positive availability slots do not overlap incorrectly.
   * @param newList New availability slot records.
   * @param oldMap Previous availability slot values, null on insert.
   */
  private static void validateNoOverlappingSlots(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    List<Availability_Slot__c> toCheck = collectChanged(newList, oldMap);

    if (toCheck.isEmpty()) {
      return;
    }

    Map<Id, List<Availability_Slot__c>> byInterviewer = groupByInterviewer(
      queryOverlappingCandidates(toCheck)
    );

    for (Availability_Slot__c slot : toCheck) {
      checkSlotOverlap(slot, byInterviewer.get(slot.Interviewer__c));
    }
  }

  /**
   * @description Groups availability slots by interviewer.
   * @param existing Existing availability slots.
   * @return Map keyed by interviewer Id.
   */
  private static Map<Id, List<Availability_Slot__c>> groupByInterviewer(
    List<Availability_Slot__c> existing
  ) {
    Map<Id, List<Availability_Slot__c>> byInterviewer = new Map<Id, List<Availability_Slot__c>>();

    for (Availability_Slot__c ex : existing) {
      if (!byInterviewer.containsKey(ex.Interviewer__c)) {
        byInterviewer.put(ex.Interviewer__c, new List<Availability_Slot__c>());
      }

      byInterviewer.get(ex.Interviewer__c).add(ex);
    }

    return byInterviewer;
  }

  /**
   * @description Adds a validation error when a slot overlaps with another active slot.
   * @param slot Availability slot being validated.
   * @param candidates Existing slots for the same interviewer.
   */
  private static void checkSlotOverlap(
    Availability_Slot__c slot,
    List<Availability_Slot__c> candidates
  ) {
    if (candidates == null) {
      return;
    }

    for (Availability_Slot__c ex : candidates) {
      if (ex.Id == slot.Id) {
        continue;
      }

      if (
        isAllowedBookedSlotOverlap(slot, ex) ||
        isAllowedBlockedSlotOverlap(slot, ex)
      ) {
        continue;
      }

      if (
        ex.Start_DateTime__c < slot.End_DateTime__c &&
        ex.End_DateTime__c > slot.Start_DateTime__c
      ) {
        slot.Start_DateTime__c.addError(
          'This interviewer already has an availability slot that overlaps with this time window.'
        );
        return;
      }
    }
  }

  /**
   * @description Allows a one-time blocked exception inside a recurring availability window.
   * @param slot New blocked exception slot.
   * @param existingSlot Existing recurring availability window.
   * @return True when the overlap is allowed.
   */
  private static Boolean isAllowedBlockedSlotOverlap(
    Availability_Slot__c slot,
    Availability_Slot__c existingSlot
  ) {
    return slot.Is_Blocked__c == true &&
      slot.Is_Recurring__c == false &&
      existingSlot.Is_Recurring__c == true &&
      existingSlot.Is_Blocked__c == false &&
      existingSlot.Is_Booked__c != true;
  }

  /**
   * @description Allows a booked one-time appointment inside a recurring availability window.
   * @param slot New booked appointment slot.
   * @param existingSlot Existing recurring availability window.
   * @return True when the overlap is allowed.
   */
  private static Boolean isAllowedBookedSlotOverlap(
    Availability_Slot__c slot,
    Availability_Slot__c existingSlot
  ) {
    return slot.Is_Booked__c == true &&
      existingSlot.Is_Recurring__c == true &&
      existingSlot.Is_Blocked__c == false &&
      existingSlot.Is_Booked__c != true;
  }
}
