trigger AvailabilitySlotTrigger on Availability_Slot__c(
  before insert,
  before update,
  after insert,
  after update
) {
  if (Trigger.isBefore) {
    AvailabilitySlotTriggerHandler.handleBeforeSave(
      Trigger.new,
      Trigger.oldMap
    );
  }

  if (Trigger.isAfter) {
    AvailabilitySlotTriggerHandler.handleAfterSave(Trigger.new, Trigger.oldMap);
  }
}
