trigger AvailabilitySlotTrigger on Availability_Slot__c (before insert, before update) {
    AvailabilitySlotTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}