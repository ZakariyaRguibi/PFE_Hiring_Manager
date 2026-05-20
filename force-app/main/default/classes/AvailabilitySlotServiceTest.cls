@IsTest
private class AvailabilitySlotServiceTest {
  // Test data helpers

  private static final Map<String, Integer> DAY_OFFSET = new Map<String, Integer>{
    'Monday' => 0,
    'Tuesday' => 1,
    'Wednesday' => 2,
    'Thursday' => 3,
    'Friday' => 4,
    'Saturday' => 5,
    'Sunday' => 6
  };

  private static User createTestInterviewer() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User u = new User(
      FirstName = 'Test',
      LastName = 'Interviewer',
      Email = 'interviewer.avail@talentforce.test',
      Username = 'interviewer.avail.' +
        Math.random() +
        '@talentforce.test.sandbox',
      Alias = 'tintv',
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'fr_MA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert u;
    return u;
  }

  private static Job_Position__c createPosition() {
    Job_Position__c pos = new Job_Position__c(
      Title__c = 'Test Position',
      Finalize_Selection__c = false
    );
    insert pos;
    return pos;
  }

  private static Interview_Stage__c createStage(
    Id positionId,
    Integer durationMin
  ) {
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = positionId,
      Stage_Number__c = 1,
      Max_Score__c = 100,
      Passing_Threshold__c = 50,
      Duration_Minutes__c = durationMin,
      Is_Active__c = false
    );
    insert stage;
    return stage;
  }

  private static Candidate__c createCandidate() {
    Candidate__c c = new Candidate__c(
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Email__c = 'test.cand.' + Math.random() + '@talentforce.test',
      Phone__c = '0600000000',
      Duplicate_Flag__c = false
    );
    insert c;
    return c;
  }

  private static Job_Application__c createApplication(
    Id positionId,
    Id candidateId
  ) {
    Job_Application__c app = new Job_Application__c(
      Job_Position__c = positionId,
      Candidate__c = candidateId,
      Passed_Hard_Filter__c = false
    );
    insert app;
    return app;
  }

  private static Interview__c createInterview(
    Id stageId,
    Id applicationId,
    Id interviewerId,
    String status
  ) {
    Interview__c iv = new Interview__c(
      Interview_Stage__c = stageId,
      Job_Application__c = applicationId,
      Interviewer__c = interviewerId,
      Status__c = status,
      Passes_To_Next_Stage__c = false
    );
    insert iv;
    return iv;
  }

  private static Availability_Slot__c createWindowFor(
    Id userId,
    String dayOfWeek,
    Integer startHour,
    Integer endHour
  ) {
    Integer offset = DAY_OFFSET.containsKey(dayOfWeek)
      ? DAY_OFFSET.get(dayOfWeek)
      : 0;
    Date baseDate = Date.newInstance(2000, 1, 3).addDays(offset);
    Availability_Slot__c slot = new Availability_Slot__c(
      Interviewer__c = userId,
      Day_Of_Week__c = dayOfWeek,
      Start_DateTime__c = DateTime.newInstance(
        baseDate,
        Time.newInstance(startHour, 0, 0, 0)
      ),
      End_DateTime__c = DateTime.newInstance(
        baseDate,
        Time.newInstance(endHour, 0, 0, 0)
      ),
      Is_Recurring__c = true,
      Is_Blocked__c = false
    );
    insert slot;
    return slot;
  }

  private static Date testMonday() {
    return Date.newInstance(2030, 1, 7);
  }

  // ── getAvailableSlotsForInterview ─────────────────────────────────────────

  @IsTest
  static void getAvailableSlots_returnsSubSlots() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c iv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Pending_Scheduling'
    );

    createWindowFor(interviewer.Id, 'Monday', 9, 12);

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForInterview(
      iv.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      3,
      slots.size(),
      '3 one-hour sub-slots from 09:00–12:00'
    );
    System.assertEquals(9, slots[0].startDt.hour());
    System.assertEquals(10, slots[1].startDt.hour());
    System.assertEquals(11, slots[2].startDt.hour());
  }

  @IsTest
  static void getAvailableSlots_excludesBookedInterviews() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c iv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Pending_Scheduling'
    );

    createWindowFor(interviewer.Id, 'Monday', 9, 12);

    Interview__c existingIv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Scheduled'
    );
    existingIv.Scheduled_DateTime__c = DateTime.newInstance(
      testMonday(),
      Time.newInstance(10, 0, 0, 0)
    );
    update existingIv;

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForInterview(
      iv.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      2,
      slots.size(),
      '10:00 is booked — only 09:00 and 11:00'
    );
  }

  @IsTest
  static void getAvailableSlots_excludesBlockedWindows() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c iv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Pending_Scheduling'
    );

    createWindowFor(interviewer.Id, 'Monday', 9, 12);

    insert new Availability_Slot__c(
      Interviewer__c = interviewer.Id,
      Day_Of_Week__c = 'Monday',
      Start_DateTime__c = DateTime.newInstance(
        testMonday(),
        Time.newInstance(9, 0, 0, 0)
      ),
      End_DateTime__c = DateTime.newInstance(
        testMonday(),
        Time.newInstance(12, 0, 0, 0)
      ),
      Is_Recurring__c = false,
      Is_Blocked__c = true
    );

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForInterview(
      iv.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(0, slots.size(), 'Blocked window returns no slots');
  }

  @IsTest
  static void getAvailableSlots_returnsEmptyWhenNoWindows() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 45);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c iv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Pending_Scheduling'
    );

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForInterview(
      iv.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(0, slots.size(), 'No windows = no slots');
  }

  @IsTest
  static void getAvailableSlots_throwsForCancelledInterview() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c iv = createInterview(
      stage.Id,
      app.Id,
      interviewer.Id,
      'Cancelled'
    );

    Boolean threw = false;
    try {
      AvailabilitySlotService.getAvailableSlotsForInterview(
        iv.Id,
        String.valueOf(testMonday())
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Should throw for cancelled interview');
  }

  // ── getAvailableSlotsForStage ────────────────────────────────────────────

  @IsTest
  static void getAvailableSlotsForStage_returnsAllSlots() {
    User interviewer1 = createTestInterviewer();
    User interviewer2 = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);

    insert new List<Interview_Stage_Team_Member__c>{
      new Interview_Stage_Team_Member__c(
        Interview_Stage__c = stage.Id,
        Interviewer__c = interviewer1.Id,
        Role__c = 'Lead'
      ),
      new Interview_Stage_Team_Member__c(
        Interview_Stage__c = stage.Id,
        Interviewer__c = interviewer2.Id,
        Role__c = 'Support'
      )
    };

    // Both have Monday 09:00–12:00 → 3 slots each = 6 total (no de-dup)
    createWindowFor(interviewer1.Id, 'Monday', 9, 12);
    createWindowFor(interviewer2.Id, 'Monday', 9, 12);

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForStage(
      stage.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      6,
      slots.size(),
      'Should return all slots from both interviewers'
    );
  }

  @IsTest
  static void getAvailableSlotsForStage_nonOverlappingWindowsReturnAll() {
    User interviewer1 = createTestInterviewer();
    User interviewer2 = createTestInterviewer();
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);

    insert new List<Interview_Stage_Team_Member__c>{
      new Interview_Stage_Team_Member__c(
        Interview_Stage__c = stage.Id,
        Interviewer__c = interviewer1.Id,
        Role__c = 'Lead'
      ),
      new Interview_Stage_Team_Member__c(
        Interview_Stage__c = stage.Id,
        Interviewer__c = interviewer2.Id,
        Role__c = 'Support'
      )
    };

    // Non-overlapping: interviewer1 morning, interviewer2 afternoon
    createWindowFor(interviewer1.Id, 'Monday', 9, 12);
    createWindowFor(interviewer2.Id, 'Monday', 14, 17);

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForStage(
      stage.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(6, slots.size(), 'Non-overlapping: 3 + 3 = 6 slots');
  }

  @IsTest
  static void getAvailableSlotsForStage_emptyWhenNoTeamMembers() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> slots = AvailabilitySlotService.getAvailableSlotsForStage(
      stage.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(0, slots.size(), 'No team members = no slots');
  }

  // ── Realistic multi-stage scenario ──────────────────────────────────────

  @IsTest
  static void scenario_booking0840_blocksStage2SlotsAt0800And0900() {
    User interviewer = createTestInterviewer();
    Job_Position__c pos = createPosition();

    Interview_Stage__c stage1 = new Interview_Stage__c(
      Job_Position__c = pos.Id,
      Stage_Number__c = 1,
      Max_Score__c = 100,
      Passing_Threshold__c = 50,
      Duration_Minutes__c = 40,
      Is_Active__c = false
    );
    insert stage1;
    Interview_Stage__c stage2 = new Interview_Stage__c(
      Job_Position__c = pos.Id,
      Stage_Number__c = 2,
      Max_Score__c = 100,
      Passing_Threshold__c = 50,
      Duration_Minutes__c = 60,
      Is_Active__c = false
    );
    insert stage2;

    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);
    Interview__c ivStage2 = createInterview(
      stage2.Id,
      app.Id,
      interviewer.Id,
      'Pending_Scheduling'
    );

    createWindowFor(interviewer.Id, 'Monday', 8, 12);

    Interview__c bookedStage1 = createInterview(
      stage1.Id,
      app.Id,
      interviewer.Id,
      'Scheduled'
    );
    bookedStage1.Scheduled_DateTime__c = DateTime.newInstance(
      testMonday(),
      Time.newInstance(8, 40, 0, 0)
    );
    update bookedStage1;

    Test.startTest();
    List<AvailabilitySlotService.TimeSlotDTO> stage2Slots = AvailabilitySlotService.getAvailableSlotsForInterview(
      ivStage2.Id,
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      2,
      stage2Slots.size(),
      'Only 10:00 and 11:00 should be free'
    );
    System.assertEquals(10, stage2Slots[0].startDt.hour());
    System.assertEquals(11, stage2Slots[1].startDt.hour());
  }
}
