@IsTest
private class InterviewerAvailabilityControllerTest {
  // ── Test data helpers ─────────────────────────────────────────────────────

  private static final Map<String, Integer> DAY_OFFSET = new Map<String, Integer>{
    'Monday' => 0,
    'Tuesday' => 1,
    'Wednesday' => 2,
    'Thursday' => 3,
    'Friday' => 4,
    'Saturday' => 5,
    'Sunday' => 6
  };

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
      Email__c = 'test.cand@talentforce.test',
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

  private static Availability_Slot__c createWindow(
    String dayOfWeek,
    Integer startHour,
    Integer endHour
  ) {
    Integer offset = DAY_OFFSET.containsKey(dayOfWeek)
      ? DAY_OFFSET.get(dayOfWeek)
      : 0;
    Date baseDate = Date.newInstance(2000, 1, 3).addDays(offset);
    Availability_Slot__c slot = new Availability_Slot__c(
      Interviewer__c = UserInfo.getUserId(),
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

  // ── getMyWindows ──────────────────────────────────────────────────────────

  @IsTest
  static void getMyWindows_returnsOwnWindows() {
    createWindow('Monday', 8, 12);
    createWindow('Friday', 14, 17);

    Test.startTest();
    List<Availability_Slot__c> windows = InterviewerAvailabilityController.getMyWindows();
    Test.stopTest();

    System.assertEquals(2, windows.size(), 'Should return 2 windows');
  }

  // ── saveWindow ────────────────────────────────────────────────────────────

  @IsTest
  static void saveWindow_insertsNewWindow() {
    Test.startTest();
    InterviewerAvailabilityController.saveWindow('Wednesday', '09:00', '11:00');
    Test.stopTest();

    List<Availability_Slot__c> inDb = [
      SELECT Id
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :UserInfo.getUserId()
        AND Day_Of_Week__c = 'Wednesday'
        AND Is_Recurring__c = TRUE
    ];
    System.assertEquals(1, inDb.size(), 'Window should exist in database');
  }

  @IsTest
  static void saveWindow_throwsOnEndBeforeStart() {
    Boolean threw = false;
    try {
      InterviewerAvailabilityController.saveWindow('Monday', '12:00', '09:00');
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Should throw for end before start');
  }

  @IsTest
  static void saveWindow_throwsOnDuplicate() {
    createWindow('Tuesday', 10, 12);
    Boolean threw = false;
    try {
      InterviewerAvailabilityController.saveWindow('Tuesday', '10:00', '12:00');
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Should throw for duplicate window');
  }

  // ── deleteWindow ──────────────────────────────────────────────────────────

  @IsTest
  static void deleteWindow_removesSlot() {
    Availability_Slot__c win = createWindow('Thursday', 13, 15);
    Test.startTest();
    InterviewerAvailabilityController.deleteWindow(win.Id);
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT Id FROM Availability_Slot__c WHERE Id = :win.Id].size(),
      'Should be deleted'
    );
  }

  // ── blockWindowForDate / unblockWindowForDate ─────────────────────────────

  @IsTest
  static void blockAndUnblock_createsAndDeletesBlockRecord() {
    Availability_Slot__c win = createWindow('Monday', 9, 11);
    Date monday = testMonday();

    Test.startTest();
    InterviewerAvailabilityController.blockWindowForDate(
      win.Id,
      String.valueOf(monday)
    );
    Test.stopTest();

    List<Availability_Slot__c> blocks = [
      SELECT Id
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :UserInfo.getUserId()
        AND Is_Recurring__c = FALSE
        AND Is_Blocked__c = TRUE
    ];
    System.assertEquals(1, blocks.size(), 'Should have created a block record');

    InterviewerAvailabilityController.unblockWindowForDate(
      win.Id,
      String.valueOf(monday)
    );

    blocks = [
      SELECT Id
      FROM Availability_Slot__c
      WHERE
        Is_Recurring__c = FALSE
        AND Is_Blocked__c = TRUE
        AND Interviewer__c = :UserInfo.getUserId()
    ];
    System.assertEquals(0, blocks.size(), 'Block should be removed');
  }

  @IsTest
  static void blockWindowForDate_idempotent() {
    Availability_Slot__c win = createWindow('Friday', 14, 16);
    Date friday = testMonday().addDays(4);

    Test.startTest();
    InterviewerAvailabilityController.blockWindowForDate(
      win.Id,
      String.valueOf(friday)
    );
    InterviewerAvailabilityController.blockWindowForDate(
      win.Id,
      String.valueOf(friday)
    );
    Test.stopTest();

    List<Availability_Slot__c> blocks = [
      SELECT Id
      FROM Availability_Slot__c
      WHERE
        Is_Recurring__c = FALSE
        AND Is_Blocked__c = TRUE
        AND Interviewer__c = :UserInfo.getUserId()
    ];
    System.assertEquals(
      1,
      blocks.size(),
      'Should only have one block (idempotent)'
    );
  }

  // ── getMyScheduledInterviews ──────────────────────────────────────────────

  @IsTest
  static void getMyScheduledInterviews_returnsScheduledForWeek() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);

    Interview__c iv = new Interview__c(
      Interview_Stage__c = stage.Id,
      Job_Application__c = app.Id,
      Interviewer__c = UserInfo.getUserId(),
      Status__c = 'Scheduled',
      Passes_To_Next_Stage__c = false,
      Scheduled_DateTime__c = DateTime.newInstance(
        testMonday(),
        Time.newInstance(9, 0, 0, 0)
      )
    );
    insert iv;

    Test.startTest();
    List<InterviewerAvailabilityController.ScheduledInterviewDTO> result = InterviewerAvailabilityController.getMyScheduledInterviews(
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      1,
      result.size(),
      'Should return 1 scheduled interview'
    );
    System.assertEquals(
      iv.Id,
      result[0].interviewId,
      'Should match interview Id'
    );
    System.assertEquals(60, result[0].durationMinutes, 'Duration should be 60');
    System.assertEquals('Monday', result[0].dayOfWeek, 'Day should be Monday');
  }

  @IsTest
  static void getMyScheduledInterviews_excludesCancelled() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);

    insert new Interview__c(
      Interview_Stage__c = stage.Id,
      Job_Application__c = app.Id,
      Interviewer__c = UserInfo.getUserId(),
      Status__c = 'Cancelled',
      Passes_To_Next_Stage__c = false,
      Scheduled_DateTime__c = DateTime.newInstance(
        testMonday(),
        Time.newInstance(10, 0, 0, 0)
      )
    );

    Test.startTest();
    List<InterviewerAvailabilityController.ScheduledInterviewDTO> result = InterviewerAvailabilityController.getMyScheduledInterviews(
      String.valueOf(testMonday())
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.size(),
      'Cancelled interviews should be excluded'
    );
  }

  @IsTest
  static void getMyScheduledInterviews_emptyForDifferentWeek() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 60);
    Candidate__c candidate = createCandidate();
    Job_Application__c app = createApplication(pos.Id, candidate.Id);

    insert new Interview__c(
      Interview_Stage__c = stage.Id,
      Job_Application__c = app.Id,
      Interviewer__c = UserInfo.getUserId(),
      Status__c = 'Scheduled',
      Passes_To_Next_Stage__c = false,
      Scheduled_DateTime__c = DateTime.newInstance(
        testMonday(),
        Time.newInstance(9, 0, 0, 0)
      )
    );

    Test.startTest();
    List<InterviewerAvailabilityController.ScheduledInterviewDTO> result = InterviewerAvailabilityController.getMyScheduledInterviews(
      String.valueOf(testMonday().addDays(7))
    );
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Different week should return empty');
  }
}
