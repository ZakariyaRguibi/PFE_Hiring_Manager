@IsTest
private class AvailabilitySlotTriggerTest {
  // ─── Test Data Setup ──────────────────────────────────────────────────────

  private static User createUser(String lastName) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User u = new User(
      LastName = lastName,
      Email = lastName.toLowerCase() + '@test.example.com',
      Username = lastName.toLowerCase() +
        '@test.example.com.' +
        System.currentTimeMillis(),
      Alias = lastName.left(8),
      TimeZoneSidKey = 'Europe/Paris',
      LocaleSidKey = 'fr_FR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert u;
    return u;
  }

  private static Availability_Slot__c buildSlot(
    Id interviewerId,
    Datetime startDt,
    Datetime endDt
  ) {
    return new Availability_Slot__c(
      Interviewer__c = interviewerId,
      Start_DateTime__c = startDt,
      End_DateTime__c = endDt
    );
  }

  // ─── Overlap Tests ────────────────────────────────────────────────────────

  @IsTest
  static void overlapSameInterviewerFails() {
    User interviewer = createUser('Smith');
    Datetime base = Datetime.now().addDays(1);

    Availability_Slot__c first = buildSlot(
      interviewer.Id,
      base,
      base.addHours(2)
    );
    insert first;

    Test.startTest();
    try {
      // Overlaps: starts 1h into existing slot
      Availability_Slot__c overlap = buildSlot(
        interviewer.Id,
        base.addHours(1),
        base.addHours(3)
      );
      insert overlap;
      System.assert(false, 'Expected exception for overlapping slot');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('overlaps'),
        'Error should mention overlap: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void overlapSameInterviewerExactAdjacentPasses() {
    User interviewer = createUser('Jones');
    Datetime base = Datetime.now().addDays(1);

    Availability_Slot__c first = buildSlot(
      interviewer.Id,
      base,
      base.addHours(2)
    );
    insert first;

    Test.startTest();
    // Starts exactly when first ends — no overlap
    Availability_Slot__c adjacent = buildSlot(
      interviewer.Id,
      base.addHours(2),
      base.addHours(4)
    );
    insert adjacent;
    Test.stopTest();

    System.assertNotEquals(
      null,
      adjacent.Id,
      'Adjacent slot should be allowed'
    );
  }

  @IsTest
  static void overlapDifferentInterviewerPasses() {
    User interviewer1 = createUser('Garcia');
    User interviewer2 = createUser('Martin');
    Datetime base = Datetime.now().addDays(1);

    Availability_Slot__c first = buildSlot(
      interviewer1.Id,
      base,
      base.addHours(2)
    );
    insert first;

    Test.startTest();
    // Same time window but different interviewer — should pass
    Availability_Slot__c second = buildSlot(
      interviewer2.Id,
      base,
      base.addHours(2)
    );
    insert second;
    Test.stopTest();

    System.assertNotEquals(
      null,
      second.Id,
      'Same time for different interviewers should be allowed'
    );
  }

  @IsTest
  static void overlapSameInterviewerNoOverlapPasses() {
    User interviewer = createUser('Durand');
    Datetime base = Datetime.now().addDays(1);

    Availability_Slot__c first = buildSlot(
      interviewer.Id,
      base,
      base.addHours(2)
    );
    insert first;

    Test.startTest();
    Availability_Slot__c second = buildSlot(
      interviewer.Id,
      base.addHours(3),
      base.addHours(5)
    );
    insert second;
    Test.stopTest();

    System.assertNotEquals(
      null,
      second.Id,
      'Non-overlapping slot for same interviewer should be allowed'
    );
  }

  @IsTest
  static void overlapUpdateToOverlapFails() {
    User interviewer = createUser('Bernard');
    Datetime base = Datetime.now().addDays(1);

    Availability_Slot__c first = buildSlot(
      interviewer.Id,
      base,
      base.addHours(2)
    );
    Availability_Slot__c second = buildSlot(
      interviewer.Id,
      base.addHours(3),
      base.addHours(5)
    );
    insert first;
    insert second;

    Test.startTest();
    try {
      // Move second slot to overlap with first
      second.Start_DateTime__c = base.addHours(1);
      second.End_DateTime__c = base.addHours(4);
      update second;
      System.assert(false, 'Expected exception when updating slot to overlap');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('overlaps'),
        'Error should mention overlap on update: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }
}
