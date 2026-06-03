/**
 * @description Tests candidate-side self-scheduling controller behavior.
 */
@IsTest
private class CandidateInterviewSchedulerCtrlTest {
  private static final String STATUS_PENDING = 'Pending_Scheduling';
  private static final String STATUS_SCHEDULED = 'Scheduled';

  private class DataBundle {
    User candidateUser;
    User interviewerA;
    User interviewerB;
    Candidate__c candidate;
    Job_Position__c job;
    Interview_Stage__c stage;
    Job_Application__c application;
    Interview__c interviewRecord;
  }

  @IsTest
  static void getPendingInterviewReturnsCandidateInterview() {
    DataBundle data = createData(true, true);

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.PendingInterviewDTO dto = CandidateInterviewSchedulerCtrl.getPendingInterview();

      System.assertNotEquals(
        null,
        dto,
        'Pending interview should be returned.'
      );
      System.assertEquals(STATUS_PENDING, dto.status);
      System.assertNotEquals(null, dto.interviewId);
      System.assertNotEquals(null, dto.schedulingDeadline);
      System.assertNotEquals(null, dto.jobTitle);
      System.assertNotEquals(null, dto.stageName);
    }
  }

  @IsTest
  static void getAvailableSlotsReturnsCandidateFacingSlotsWithoutInterviewerDetails() {
    DataBundle data = createData(true, true);

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        data.interviewRecord.Id,
        weekStartFor(firstBookableStart())
      );

      System.assert(
        !slots.isEmpty(),
        'Candidate should see available public slots.'
      );

      for (AvailabilitySlotService.TimeSlotDTO slot : slots) {
        System.assertEquals(
          null,
          slot.interviewerId,
          'Candidate-facing slots must hide interviewer id.'
        );
        System.assertEquals(
          null,
          slot.interviewerName,
          'Candidate-facing slots must hide interviewer name.'
        );
        System.assertEquals(
          null,
          slot.availabilitySlotId,
          'Candidate-facing slots must hide raw availability id.'
        );
      }
    }
  }

  @IsTest
  static void markCandidateTriedToScheduleUpdatesInterviewWithoutScheduling() {
    DataBundle data = createData(true, true);

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.markCandidateTriedToSchedule(
        data.interviewRecord.Id
      );
    }

    Interview__c updatedInterview = [
      SELECT Candidate_Tried_To_Schedule__c, Status__c, Scheduled_DateTime__c
      FROM Interview__c
      WHERE Id = :data.interviewRecord.Id
      LIMIT 1
    ];

    System.assertEquals(true, updatedInterview.Candidate_Tried_To_Schedule__c);
    System.assertEquals(STATUS_PENDING, updatedInterview.Status__c);
    System.assertEquals(null, updatedInterview.Scheduled_DateTime__c);
  }

  @IsTest
  static void scheduleInterviewUpdatesInterviewAssignsInterviewerAndBooksSlot() {
    DataBundle data = createData(true, true);

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        data.interviewRecord.Id,
        weekStartFor(firstBookableStart())
      );

      System.assert(
        !slots.isEmpty(),
        'At least one slot must be available before scheduling.'
      );
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        data.interviewRecord.Id,
        String.valueOf(slots[0].startDt)
      );
    }

    Interview__c updatedInterview = [
      SELECT
        Status__c,
        Scheduled_DateTime__c,
        Interviewer__c,
        Availability_Slot__c,
        Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :data.interviewRecord.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, updatedInterview.Status__c);
    System.assertNotEquals(null, updatedInterview.Scheduled_DateTime__c);
    System.assertNotEquals(null, updatedInterview.Interviewer__c);
    System.assertNotEquals(null, updatedInterview.Availability_Slot__c);
    System.assertEquals(true, updatedInterview.Candidate_Tried_To_Schedule__c);
  }

  @IsTest
  static void scheduleInterviewFromNonRecurringPositiveAvailabilityWorks() {
    DataBundle data = createData(false, false);

    Datetime selectedStart = Datetime.newInstance(
      Date.today().addDays(6),
      Time.newInstance(14, 0, 0, 0)
    );

    Availability_Slot__c nonRecurringSlot = new Availability_Slot__c(
      Interviewer__c = data.interviewerA.Id,
      Interview_Stage__c = null,
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Is_Booked__c = false,
      Day_Of_Week__c = selectedStart.format('EEEE'),
      Start_DateTime__c = selectedStart,
      End_DateTime__c = selectedStart.addMinutes(30)
    );

    insert as system nonRecurringSlot;

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        data.interviewRecord.Id,
        weekStartFor(selectedStart)
      );

      System.assert(
        !slots.isEmpty(),
        'Candidate should see non-recurring positive availability.'
      );

      CandidateInterviewSchedulerCtrl.scheduleInterview(
        data.interviewRecord.Id,
        String.valueOf(selectedStart)
      );
    }

    Interview__c updatedInterview = [
      SELECT
        Status__c,
        Scheduled_DateTime__c,
        Interviewer__c,
        Availability_Slot__c,
        Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :data.interviewRecord.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, updatedInterview.Status__c);
    System.assertEquals(selectedStart, updatedInterview.Scheduled_DateTime__c);
    System.assertEquals(data.interviewerA.Id, updatedInterview.Interviewer__c);
    System.assertNotEquals(null, updatedInterview.Availability_Slot__c);
    System.assertEquals(true, updatedInterview.Candidate_Tried_To_Schedule__c);

    Availability_Slot__c updatedSlot = [
      SELECT Is_Booked__c, Booked_Interview__c
      FROM Availability_Slot__c
      WHERE Id = :nonRecurringSlot.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      updatedSlot.Is_Booked__c,
      'Non-recurring availability should be marked as booked.'
    );

    System.assertEquals(
      updatedInterview.Id,
      updatedSlot.Booked_Interview__c,
      'Non-recurring slot should reference the scheduled interview.'
    );
  }

  @IsTest
  static void getAvailableSlotsBlocksExpiredDeadline() {
    DataBundle data = createData(true, true);

    data.interviewRecord.Scheduling_Deadline__c = System.now().addDays(-1);
    update as system data.interviewRecord;

    Boolean exceptionThrown = false;

    System.runAs(data.candidateUser) {
      try {
        CandidateInterviewSchedulerCtrl.getAvailableSlots(
          data.interviewRecord.Id,
          weekStartFor(firstBookableStart())
        );
      } catch (AuraHandledException expectedException) {
        exceptionThrown = true;
      }
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'Expired scheduling deadline should block slot loading.'
    );
  }

  @IsTest
  static void scheduleInterviewBlocksCandidateOverlap() {
    DataBundle data = createData(true, true);
    Datetime selectedStart = firstBookableStart();

    Interview__c existingScheduledInterview = new Interview__c(
      Job_Application__c = data.application.Id,
      Interview_Stage__c = data.stage.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = selectedStart,
      Scheduling_Deadline__c = System.now().addDays(7)
    );
    insert as system existingScheduledInterview;

    Boolean exceptionThrown = false;

    System.runAs(data.candidateUser) {
      try {
        CandidateInterviewSchedulerCtrl.markCandidateTriedToSchedule(
          data.interviewRecord.Id
        );
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          data.interviewRecord.Id,
          String.valueOf(selectedStart)
        );
      } catch (AuraHandledException expectedException) {
        exceptionThrown = true;
      }
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'Candidate should not be allowed to book overlapping interviews.'
    );
  }

  @IsTest
  static void scheduleInterviewUsesAlternativeInterviewerWhenSameInterviewerIsTaken() {
    DataBundle data = createData(true, true);
    Datetime selectedStart = firstBookableStart();

    Job_Application__c competingApplication = createApplicationForDifferentCandidate(
      data.job.Id,
      data.stage.Id
    );

    Interview__c competingInterview = new Interview__c(
      Job_Application__c = competingApplication.Id,
      Interview_Stage__c = data.stage.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = selectedStart,
      Scheduling_Deadline__c = System.now().addDays(7)
    );
    insert as system competingInterview;

    insert as system new Availability_Slot__c(
      Interviewer__c = data.interviewerA.Id,
      Interview_Stage__c = data.stage.Id,
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Is_Booked__c = true,
      Booked_Interview__c = competingInterview.Id,
      Day_Of_Week__c = selectedStart.format('EEEE'),
      Start_DateTime__c = selectedStart,
      End_DateTime__c = selectedStart.addMinutes(30)
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        data.interviewRecord.Id,
        String.valueOf(selectedStart)
      );
    }

    Interview__c updatedInterview = [
      SELECT Status__c, Interviewer__c
      FROM Interview__c
      WHERE Id = :data.interviewRecord.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, updatedInterview.Status__c);
    System.assertEquals(
      data.interviewerB.Id,
      updatedInterview.Interviewer__c,
      'The remaining eligible interviewer should be assigned when interviewer A is taken.'
    );
  }

  @IsTest
  static void scheduleInterviewFailsWhenAllInterviewersAreTaken() {
    DataBundle data = createData(true, false);
    Datetime selectedStart = firstBookableStart();

    Job_Application__c competingApplication = createApplicationForDifferentCandidate(
      data.job.Id,
      data.stage.Id
    );

    Interview__c competingInterview = new Interview__c(
      Job_Application__c = competingApplication.Id,
      Interview_Stage__c = data.stage.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = selectedStart,
      Scheduling_Deadline__c = System.now().addDays(7)
    );
    insert as system competingInterview;

    insert as system new Availability_Slot__c(
      Interviewer__c = data.interviewerA.Id,
      Interview_Stage__c = data.stage.Id,
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Is_Booked__c = true,
      Booked_Interview__c = competingInterview.Id,
      Day_Of_Week__c = selectedStart.format('EEEE'),
      Start_DateTime__c = selectedStart,
      End_DateTime__c = selectedStart.addMinutes(30)
    );

    Boolean exceptionThrown = false;

    System.runAs(data.candidateUser) {
      try {
        CandidateInterviewSchedulerCtrl.markCandidateTriedToSchedule(
          data.interviewRecord.Id
        );
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          data.interviewRecord.Id,
          String.valueOf(selectedStart)
        );
      } catch (AuraHandledException expectedException) {
        exceptionThrown = true;
      }
    }

    System.assertEquals(
      true,
      exceptionThrown,
      'Scheduling should fail when all eligible interviewers are already taken.'
    );

    Interview__c resultInterview = [
      SELECT Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :data.interviewRecord.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      resultInterview.Candidate_Tried_To_Schedule__c,
      'A failed confirm attempt should still be tracked when it was explicitly recorded before scheduling.'
    );
  }

  @IsTest
  static void getPendingInterviewReturnsNullWhenThereIsNoPendingInterview() {
    DataBundle data = createData(true, true);

    data.interviewRecord.Status__c = STATUS_SCHEDULED;
    data.interviewRecord.Interviewer__c = data.interviewerA.Id;
    data.interviewRecord.Scheduled_DateTime__c = firstBookableStart();
    update as system data.interviewRecord;

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.PendingInterviewDTO dto = CandidateInterviewSchedulerCtrl.getPendingInterview();

      System.assertEquals(
        null,
        dto,
        'No pending interview should be returned when the interview is already scheduled.'
      );
    }
  }

  private static DataBundle createData(
    Boolean createRecurringAvailability,
    Boolean secondInterviewer
  ) {
    DataBundle data = new DataBundle();
    Long seed = uniqueSeed();

    Profile profileRecord = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    data.candidateUser = buildUser(
      'Portal' + seed,
      'Candidate',
      'pc' + seed,
      profileRecord.Id
    );
    data.interviewerA = buildUser(
      'Interviewer' + seed,
      'A',
      'ia' + seed,
      profileRecord.Id
    );

    List<User> users = new List<User>{ data.candidateUser, data.interviewerA };

    if (secondInterviewer == true) {
      data.interviewerB = buildUser(
        'Interviewer' + seed,
        'B',
        'ib' + seed,
        profileRecord.Id
      );
      users.add(data.interviewerB);
    }

    insert as system users;

    data.candidate = new Candidate__c(
      FirstName__c = 'Portal' + seed,
      LastName__c = 'Candidate',
      Phone__c = '+212600' + String.valueOf(seed).right(6),
      Email__c = 'portal.candidate.' + seed + '@example.com',
      User__c = data.candidateUser.Id
    );
    insert as system data.candidate;

    data.job = new Job_Position__c(
      Title__c = 'Candidate Scheduler Job ' + seed,
      Status__c = 'Draft',
      Portal_Description__c = 'Test portal description',
      Detailed_Tasks__c = 'Test detailed tasks',
      Evaluation_Criteria__c = 'Test evaluation criteria',
      Application_Deadline__c = Date.today().addDays(30),
      Desired_Hires__c = 1,
      Max_Interview_Candidates__c = 10
    );
    insert as system data.job;

    data.stage = new Interview_Stage__c(
      Name = 'HR Screening ' + seed,
      Job_Position__c = data.job.Id,
      Stage_Number__c = 1,
      Duration_Minutes__c = 30,
      Stage_Weight__c = 100,
      Max_Score__c = 20,
      Passing_Threshold__c = 12
    );
    insert as system data.stage;

    insertTeamMember(data.stage.Id, data.interviewerA.Id);

    if (secondInterviewer == true) {
      insertTeamMember(data.stage.Id, data.interviewerB.Id);
    }

    if (createRecurringAvailability == true) {
      insertRecurringAvailabilityForAllWeekDays(null, data.interviewerA.Id);

      if (secondInterviewer == true) {
        insertRecurringAvailabilityForAllWeekDays(null, data.interviewerB.Id);
      }
    }

    data.application = new Job_Application__c(
      Candidate__c = data.candidate.Id,
      Job_Position__c = data.job.Id,
      Stage__c = 'New'
    );
    insert as system data.application;

    data.interviewRecord = new Interview__c(
      Job_Application__c = data.application.Id,
      Interview_Stage__c = data.stage.Id,
      Status__c = STATUS_PENDING,
      Scheduled_DateTime__c = null,
      Scheduling_Deadline__c = System.now().addDays(7)
    );
    insert as system data.interviewRecord;

    return data;
  }

  private static Job_Application__c createApplicationForDifferentCandidate(
    Id jobId,
    Id stageId
  ) {
    Long seed = uniqueSeed();

    Candidate__c otherCandidate = new Candidate__c(
      FirstName__c = 'Other' + seed,
      LastName__c = 'Candidate',
      Phone__c = '+212601' + String.valueOf(seed).right(6),
      Email__c = 'other.candidate.' + seed + '@example.com'
    );
    insert as system otherCandidate;

    Job_Application__c otherApplication = new Job_Application__c(
      Candidate__c = otherCandidate.Id,
      Job_Position__c = jobId,
      Stage__c = 'Interview',
      Current_Interview_Stage__c = stageId
    );
    insert as system otherApplication;

    return otherApplication;
  }

  private static User buildUser(
    String firstName,
    String lastName,
    String aliasPrefix,
    Id profileId
  ) {
    String uniqueText = aliasPrefix + String.valueOf(uniqueSeed());

    return new User(
      FirstName = firstName,
      LastName = lastName,
      Alias = uniqueText.left(8),
      Email = uniqueText + '@example.com',
      Username = uniqueText + '@example.com',
      CommunityNickname = uniqueText.left(40),
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = profileId
    );
  }

  private static void insertTeamMember(Id stageId, Id interviewerId) {
    Interview_Stage_Team_Member__c member = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stageId,
      Interviewer__c = interviewerId
    );

    List<Schema.PicklistEntry> roleValues = Interview_Stage_Team_Member__c.Role__c.getDescribe()
      .getPicklistValues();

    if (!roleValues.isEmpty()) {
      member.Role__c = roleValues[0].getValue();
    }

    insert as system member;
  }

  private static void insertRecurringAvailabilityForAllWeekDays(
    Id stageId,
    Id interviewerId
  ) {
    List<String> days = new List<String>{
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    };

    Date baseDate = Date.newInstance(2000, 1, 3);
    List<Availability_Slot__c> records = new List<Availability_Slot__c>();

    for (Integer index = 0; index < days.size(); index++) {
      Date windowDate = baseDate.addDays(index);

      records.add(
        new Availability_Slot__c(
          Interviewer__c = interviewerId,
          Interview_Stage__c = stageId,
          Is_Recurring__c = true,
          Is_Blocked__c = false,
          Is_Booked__c = false,
          Day_Of_Week__c = days[index],
          Start_DateTime__c = Datetime.newInstance(
            windowDate,
            Time.newInstance(9, 0, 0, 0)
          ),
          End_DateTime__c = Datetime.newInstance(
            windowDate,
            Time.newInstance(12, 0, 0, 0)
          )
        )
      );
    }

    insert as system records;
  }

  private static Datetime firstBookableStart() {
    return Datetime.newInstance(
      Date.today().addDays(5),
      Time.newInstance(9, 0, 0, 0)
    );
  }

  private static String weekStartFor(Datetime value) {
    Date baseMonday = Date.newInstance(1900, 1, 1);
    Integer offset = Math.mod(baseMonday.daysBetween(value.date()), 7);

    if (offset < 0) {
      offset += 7;
    }

    return String.valueOf(value.date().addDays(-offset));
  }

  private static Long uniqueSeed() {
    return System.currentTimeMillis() +
      Limits.getDmlRows() +
      Math.abs(Crypto.getRandomInteger());
  }
}
