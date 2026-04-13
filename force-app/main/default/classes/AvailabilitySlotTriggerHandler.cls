public inherited sharing class AvailabilitySlotTriggerHandler {
  public static void handle(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    validateNoOverlappingSlots(newList, oldMap);
  }

  /**
   * No overlapping slots for the same interviewer.
   * Two slots overlap if one starts before the other ends.
   */
  @SuppressWarnings('PMD.ApexCRUDViolation') // Trigger handler runs in system mode by design
  private static void validateNoOverlappingSlots(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    List<Availability_Slot__c> toCheck = new List<Availability_Slot__c>();
    for (Availability_Slot__c slot : newList) {
      if (
        slot.Interviewer__c == null ||
        slot.Start_DateTime__c == null ||
        slot.End_DateTime__c == null
      )
        continue;
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
    if (toCheck.isEmpty())
      return;

    Set<Id> interviewerIds = new Set<Id>();
    Datetime minStart = null;
    Datetime maxEnd = null;
    for (Availability_Slot__c slot : toCheck) {
      interviewerIds.add(slot.Interviewer__c);
      if (minStart == null || slot.Start_DateTime__c < minStart)
        minStart = slot.Start_DateTime__c;
      if (maxEnd == null || slot.End_DateTime__c > maxEnd)
        maxEnd = slot.End_DateTime__c;
    }

    List<Availability_Slot__c> existing = [
      SELECT Id, Interviewer__c, Start_DateTime__c, End_DateTime__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Start_DateTime__c < :maxEnd
        AND End_DateTime__c > :minStart
    ];

    for (Availability_Slot__c slot : toCheck) {
      for (Availability_Slot__c ex : existing) {
        if (ex.Id == slot.Id)
          continue;
        if (ex.Interviewer__c != slot.Interviewer__c)
          continue;
        // Check overlap: existing.start < slot.end AND existing.end > slot.start
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
