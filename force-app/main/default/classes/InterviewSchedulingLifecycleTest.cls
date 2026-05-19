/**
 * @description End-to-end tests for the TalentForce interview scheduling lifecycle.
 */
@IsTest
private class InterviewSchedulingLifecycleTest {
  private static final String APP_STAGE_NEW = 'New';
  private static final String APP_STAGE_INTERVIEW = 'Interview';
  private static final String APP_STAGE_WITHDRAWN = 'Withdrawn';

  private static final String STATUS_PENDING = 'Pending_Scheduling';
  private static final String STATUS_SCHEDULED = 'Scheduled';
  private static final String STATUS_CANCELLED = 'Cancelled';

  private class DataBundle {
    User candidateUser;
    User interviewerA;
    User interviewerB;
    Candidate__c candidate;
    Job_Position__c job;
    Interview_Stage__c stage1;
    Interview_Stage__c stage2;
    Interview_Stage__c stage3;
    Job_Application__c application;
  }

  @IsTest
  static void enteringInterviewSetsFirstStageAndCreatesPendingInterview() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Job_Application__c refreshedApplication = [
      SELECT Stage__c, Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(APP_STAGE_INTERVIEW, refreshedApplication.Stage__c);
    System.assertEquals(
      data.stage1.Id,
      refreshedApplication.Current_Interview_Stage__c
    );

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.assertEquals(STATUS_PENDING, pendingInterview.Status__c);
    System.assertEquals(null, pendingInterview.Interviewer__c);
    System.assertEquals(null, pendingInterview.Scheduled_DateTime__c);
    System.assertNotEquals(null, pendingInterview.Scheduling_Deadline__c);
  }

  @IsTest
  static void enteringInterviewWithoutAvailabilityCreatesNoInterview() {
    DataBundle data = createLifecycleData(1, true, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Job_Application__c refreshedApplication = [
      SELECT Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(
      data.stage1.Id,
      refreshedApplication.Current_Interview_Stage__c
    );
    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage1.Id)
    );
  }

  @IsTest
  static void enteringInterviewWithoutTeamMemberCreatesNoInterview() {
    DataBundle data = createLifecycleData(1, false, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Job_Application__c refreshedApplication = [
      SELECT Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(
      data.stage1.Id,
      refreshedApplication.Current_Interview_Stage__c
    );
    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage1.Id)
    );
  }

  @IsTest
  static void teamMemberAddedLaterRetriesOnlyApplicationsOnThatStage() {
    DataBundle data = createLifecycleData(1, false, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage1.Id)
    );

    insertTeamMember(data.stage1.Id, data.interviewerA.Id);
    insertRecurringAvailabilityForAllWeekDays(null, data.interviewerA.Id);

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    System.assertEquals(STATUS_PENDING, pendingInterview.Status__c);
  }

  @IsTest
  static void availabilityAddedLaterRetriesWaitingApplications() {
    DataBundle data = createLifecycleData(1, true, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage1.Id)
    );

    insertRecurringAvailabilityForAllWeekDays(null, data.interviewerA.Id);

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    System.assertEquals(STATUS_PENDING, pendingInterview.Status__c);
  }

  @IsTest
  static void nonRecurringAvailabilityAddedLaterCreatesPendingInterview() {
    DataBundle data = createLifecycleData(1, true, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage1.Id)
    );

    Datetime startDt = firstBookableStart();

    insert as system new Availability_Slot__c(
      Interviewer__c = data.interviewerA.Id,
      Interview_Stage__c = null,
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Is_Booked__c = false,
      Day_Of_Week__c = startDt.format('EEEE'),
      Start_DateTime__c = startDt,
      End_DateTime__c = startDt.addHours(3)
    );

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    System.assertEquals(STATUS_PENDING, pendingInterview.Status__c);
  }

  @IsTest
  static void stageProgressionCreatesAndSchedulesPendingInterviewUntilLastStage() {
    DataBundle data = createLifecycleData(3, true, true, true, false);

    Test.startTest();

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    scheduleAsCandidate(data.candidateUser, stage1Interview.Id);

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    Interview__c stage2Interview = getOnlyInterview(
      data.application.Id,
      data.stage2.Id
    );
    System.assertEquals(STATUS_PENDING, stage2Interview.Status__c);
    scheduleAsCandidate(data.candidateUser, stage2Interview.Id);

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage3.Id
    );

    Interview__c stage3Interview = getOnlyInterview(
      data.application.Id,
      data.stage3.Id
    );
    System.assertEquals(STATUS_PENDING, stage3Interview.Status__c);
    scheduleAsCandidate(data.candidateUser, stage3Interview.Id);

    Test.stopTest();

    List<Interview__c> scheduledInterviews = [
      SELECT
        Id,
        Status__c,
        Interviewer__c,
        Scheduled_DateTime__c,
        Availability_Slot__c
      FROM Interview__c
      WHERE Job_Application__c = :data.application.Id
      ORDER BY CreatedDate ASC
    ];

    System.assertEquals(3, scheduledInterviews.size());

    for (Interview__c interviewRecord : scheduledInterviews) {
      System.assertEquals(STATUS_SCHEDULED, interviewRecord.Status__c);
      System.assertNotEquals(null, interviewRecord.Interviewer__c);
      System.assertNotEquals(null, interviewRecord.Scheduled_DateTime__c);
      System.assertNotEquals(null, interviewRecord.Availability_Slot__c);
    }
  }

  @IsTest
  static void currentStageChangeDoesNotDuplicateExistingPendingInterview() {
    DataBundle data = createLifecycleData(2, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Job_Application__c appToStage2 = [
      SELECT Id, Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];
    appToStage2.Current_Interview_Stage__c = data.stage2.Id;
    update as system appToStage2;

    appToStage2 = [
      SELECT Id, Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];
    update as system appToStage2;

    System.assertEquals(
      1,
      countInterviews(data.application.Id, data.stage2.Id)
    );
  }

  @IsTest
  static void expiredPendingInterviewWithHistoricalSlotsIsCancelledAndApplicationWithdrawn() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    Test.setCreatedDate(pendingInterview.Id, System.now().addDays(-10));

    pendingInterview = [
      SELECT Id, Scheduling_Deadline__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];
    pendingInterview.Scheduling_Deadline__c = System.now().addDays(-2);
    update as system pendingInterview;

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Interview__c resultInterview = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    Job_Application__c resultApplication = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_CANCELLED, resultInterview.Status__c);
    System.assertEquals(APP_STAGE_WITHDRAWN, resultApplication.Stage__c);
  }

  @IsTest
  static void expiredPendingInterviewAfterCandidateAttemptIsNotWithdrawn() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    Test.setCreatedDate(pendingInterview.Id, System.now().addDays(-10));

    update as system new Interview__c(
      Id = pendingInterview.Id,
      Scheduling_Deadline__c = System.now().addDays(-2),
      Candidate_Tried_To_Schedule__c = true
    );

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Interview__c resultInterview = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    Job_Application__c resultApplication = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
    System.assertEquals(APP_STAGE_INTERVIEW, resultApplication.Stage__c);
  }

  @IsTest
  static void expiredPendingInterviewWithoutSlotsIsNotCancelledAndApplicationNotWithdrawn() {
    DataBundle data = createLifecycleData(1, true, false, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c manualPendingInterview = new Interview__c(
      Job_Application__c = data.application.Id,
      Interview_Stage__c = data.stage1.Id,
      Status__c = STATUS_PENDING,
      Scheduling_Deadline__c = System.now().addDays(-2)
    );
    insert as system manualPendingInterview;

    Test.setCreatedDate(manualPendingInterview.Id, System.now().addDays(-10));

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Interview__c resultInterview = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :manualPendingInterview.Id
      LIMIT 1
    ];

    Job_Application__c resultApplication = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
    System.assertEquals(APP_STAGE_INTERVIEW, resultApplication.Stage__c);
  }

  @IsTest
  static void futurePendingInterviewIsIgnoredByDeadlineBatch() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Interview__c resultInterview = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
  }

  @IsTest
  static void scheduledInterviewIsIgnoredByDeadlineBatch() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    scheduleAsCandidate(data.candidateUser, pendingInterview.Id);

    Interview__c scheduledInterview = [
      SELECT Id, Status__c, Scheduling_Deadline__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    scheduledInterview.Scheduling_Deadline__c = System.now().addDays(-2);
    update as system scheduledInterview;

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Interview__c resultInterview = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, resultInterview.Status__c);
  }

  @IsTest
  static void schedulingFromRecurringAvailabilityCreatesBookedInstanceAndKeepsRecurringWindowOpen() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(firstBookableStart())
      );

      System.assert(
        !slots.isEmpty(),
        'Candidate should see at least one recurring slot.'
      );

      CandidateInterviewSchedulerCtrl.scheduleInterview(
        pendingInterview.Id,
        String.valueOf(slots[0].startDt)
      );
    }

    Interview__c scheduledInterview = [
      SELECT
        Id,
        Status__c,
        Interviewer__c,
        Scheduled_DateTime__c,
        Availability_Slot__c,
        Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, scheduledInterview.Status__c);
    System.assertEquals(
      true,
      scheduledInterview.Candidate_Tried_To_Schedule__c
    );
    System.assertNotEquals(null, scheduledInterview.Interviewer__c);
    System.assertNotEquals(null, scheduledInterview.Scheduled_DateTime__c);
    System.assertNotEquals(null, scheduledInterview.Availability_Slot__c);

    Availability_Slot__c bookedSlot = [
      SELECT
        Id,
        Interviewer__c,
        Is_Recurring__c,
        Is_Booked__c,
        Booked_Interview__c,
        Start_DateTime__c,
        End_DateTime__c
      FROM Availability_Slot__c
      WHERE Id = :scheduledInterview.Availability_Slot__c
      LIMIT 1
    ];

    System.assertEquals(false, bookedSlot.Is_Recurring__c);
    System.assertEquals(true, bookedSlot.Is_Booked__c);
    System.assertEquals(scheduledInterview.Id, bookedSlot.Booked_Interview__c);
    System.assertEquals(
      scheduledInterview.Interviewer__c,
      bookedSlot.Interviewer__c
    );
    System.assertEquals(
      scheduledInterview.Scheduled_DateTime__c,
      bookedSlot.Start_DateTime__c
    );

    Integer bookedRecurringWindows = [
      SELECT COUNT()
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :scheduledInterview.Interviewer__c
        AND Is_Recurring__c = TRUE
        AND Is_Booked__c = TRUE
    ];

    System.assertEquals(
      0,
      bookedRecurringWindows,
      'Recurring availability must remain a reusable definition and must not be booked directly.'
    );
  }

  @IsTest
  static void candidateAttemptIsPreservedWhenSelectedSlotBecomesUnavailable() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    List<AvailabilitySlotService.TimeSlotDTO> slots;
    System.runAs(data.candidateUser) {
      slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(firstBookableStart())
      );
    }

    System.assert(!slots.isEmpty(), 'Candidate should see at least one slot.');

    Datetime selectedStart = slots[0].startDt;
    Datetime selectedEnd = slots[0].endDt;

    User otherCandidateUser = buildUser(
      'Other' + uniqueSeed(),
      'Candidate',
      'othercand' + uniqueSeed(),
      data.candidateUser.ProfileId
    );
    insert as system otherCandidateUser;

    Candidate__c otherCandidate = new Candidate__c(
      FirstName__c = 'Other',
      LastName__c = 'Candidate',
      Phone__c = '+2126' + String.valueOf(uniqueSeed()).right(8),
      Email__c = 'other.candidate.' + uniqueSeed() + '@example.com',
      User__c = otherCandidateUser.Id
    );
    insert as system otherCandidate;

    Job_Application__c otherApplication = new Job_Application__c(
      Candidate__c = otherCandidate.Id,
      Job_Position__c = data.job.Id,
      Stage__c = APP_STAGE_INTERVIEW,
      Current_Interview_Stage__c = data.stage1.Id
    );
    insert as system otherApplication;

    insert as system new Interview__c(
      Job_Application__c = otherApplication.Id,
      Interview_Stage__c = data.stage1.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = selectedStart,
      Scheduling_Deadline__c = System.now().addDays(7)
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.markCandidateTriedToSchedule(
        pendingInterview.Id
      );

      try {
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          pendingInterview.Id,
          String.valueOf(selectedStart)
        );
        System.assert(
          false,
          'Scheduling should fail because the only interviewer became unavailable.'
        );
      } catch (Exception expectedException) {
        System.assertNotEquals(
          null,
          expectedException,
          'Expected scheduling failure was captured.'
        );
      }
    }

    Interview__c resultInterview = [
      SELECT
        Status__c,
        Scheduled_DateTime__c,
        Interviewer__c,
        Availability_Slot__c,
        Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
    System.assertEquals(null, resultInterview.Scheduled_DateTime__c);
    System.assertEquals(null, resultInterview.Interviewer__c);
    System.assertEquals(null, resultInterview.Availability_Slot__c);
    System.assertEquals(
      true,
      resultInterview.Candidate_Tried_To_Schedule__c,
      'The candidate attempt must stay recorded even when confirmation fails.'
    );

    update as system new Interview__c(
      Id = pendingInterview.Id,
      Scheduling_Deadline__c = System.now().addDays(-2)
    );

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    Job_Application__c resultApplication = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(
      APP_STAGE_INTERVIEW,
      resultApplication.Stage__c,
      'The batch must not withdraw an application when the candidate already tried to schedule.'
    );
  }

  @IsTest
  static void candidateCannotScheduleBeforeMinimumOffset() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    Datetime tooEarlyStart = System.now().addHours(1);

    System.runAs(data.candidateUser) {
      try {
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          pendingInterview.Id,
          String.valueOf(tooEarlyStart)
        );
        System.assert(
          false,
          'Scheduling before the minimum offset should fail.'
        );
      } catch (Exception expectedException) {
        System.assertNotEquals(
          null,
          expectedException,
          'Expected minimum offset failure was captured.'
        );
      }
    }

    Interview__c resultInterview = [
      SELECT Status__c, Scheduled_DateTime__c, Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
    System.assertEquals(null, resultInterview.Scheduled_DateTime__c);
    System.assertNotEquals(
      true,
      resultInterview.Candidate_Tried_To_Schedule__c
    );
  }

  @IsTest
  static void candidateCannotScheduleAfterDeadline() {
    DataBundle data = createLifecycleData(1, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    update as system new Interview__c(
      Id = pendingInterview.Id,
      Scheduling_Deadline__c = System.now().addDays(-1)
    );

    System.runAs(data.candidateUser) {
      try {
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          pendingInterview.Id,
          String.valueOf(firstBookableStart())
        );
        System.assert(false, 'Scheduling after the deadline should fail.');
      } catch (Exception expectedException) {
        System.assertNotEquals(
          null,
          expectedException,
          'Expected deadline failure was captured.'
        );
      }
    }

    Interview__c resultInterview = [
      SELECT Status__c, Scheduled_DateTime__c, Candidate_Tried_To_Schedule__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_PENDING, resultInterview.Status__c);
    System.assertEquals(null, resultInterview.Scheduled_DateTime__c);
    System.assertNotEquals(
      true,
      resultInterview.Candidate_Tried_To_Schedule__c
    );
  }

  @IsTest
  static void applicationStageChangedWhileAlreadyInterviewCreatesCurrentStageInterview() {
    DataBundle data = createLifecycleData(2, true, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    System.assertEquals(
      1,
      countInterviews(data.application.Id, data.stage1.Id)
    );

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    Interview__c stage2Interview = getOnlyInterview(
      data.application.Id,
      data.stage2.Id
    );
    System.assertEquals(STATUS_PENDING, stage2Interview.Status__c);

    Job_Application__c resultApplication = [
      SELECT Stage__c, Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(APP_STAGE_INTERVIEW, resultApplication.Stage__c);
    System.assertEquals(
      data.stage2.Id,
      resultApplication.Current_Interview_Stage__c
    );
  }

  @IsTest
  static void stageProgressionWithoutAvailabilityWaitsThenRetriesWhenAvailabilityIsAdded() {
    DataBundle data = createLifecycleData(2, true, false, true, false);

    insertNonRecurringAvailability(
      data.stage1.Id,
      data.interviewerA.Id,
      firstBookableStart(),
      3
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    scheduleAsCandidate(data.candidateUser, stage1Interview.Id);

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    Job_Application__c waitingApplication = [
      SELECT Stage__c, Current_Interview_Stage__c
      FROM Job_Application__c
      WHERE Id = :data.application.Id
      LIMIT 1
    ];

    System.assertEquals(APP_STAGE_INTERVIEW, waitingApplication.Stage__c);
    System.assertEquals(
      data.stage2.Id,
      waitingApplication.Current_Interview_Stage__c
    );
    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage2.Id),
      'No Stage 2 interview should be created until Stage 2 availability exists.'
    );

    insertNonRecurringAvailability(
      data.stage2.Id,
      data.interviewerA.Id,
      firstBookableStart().addDays(1),
      3
    );

    Interview__c stage2Interview = getOnlyInterview(
      data.application.Id,
      data.stage2.Id
    );
    System.assertEquals(STATUS_PENDING, stage2Interview.Status__c);
    System.assertEquals(null, stage2Interview.Scheduled_DateTime__c);
  }

  @IsTest
  static void stageProgressionWithoutTeamMemberWaitsUntilTeamMemberAndAvailabilityExist() {
    DataBundle data = createLifecycleData(2, false, false, true, false);

    insertTeamMember(data.stage1.Id, data.interviewerA.Id);
    insertNonRecurringAvailability(
      data.stage1.Id,
      data.interviewerA.Id,
      firstBookableStart(),
      3
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    scheduleAsCandidate(data.candidateUser, stage1Interview.Id);

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage2.Id),
      'No Stage 2 interview should be created because Stage 2 has no team member.'
    );

    insertNonRecurringAvailability(
      data.stage2.Id,
      data.interviewerA.Id,
      firstBookableStart().addDays(1),
      3
    );

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage2.Id),
      'Adding availability only should not create Stage 2 interview while no team member exists.'
    );

    insertTeamMember(data.stage2.Id, data.interviewerA.Id);

    Interview__c stage2Interview = getOnlyInterview(
      data.application.Id,
      data.stage2.Id
    );
    System.assertEquals(STATUS_PENDING, stage2Interview.Status__c);
  }

  @IsTest
  static void stageWaitingForAvailabilityDoesNotDuplicateWhenMoreAvailabilityIsAdded() {
    DataBundle data = createLifecycleData(2, true, false, true, false);

    insertNonRecurringAvailability(
      data.stage1.Id,
      data.interviewerA.Id,
      firstBookableStart(),
      3
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    scheduleAsCandidate(data.candidateUser, stage1Interview.Id);

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    System.assertEquals(
      0,
      countInterviews(data.application.Id, data.stage2.Id)
    );

    insertNonRecurringAvailability(
      data.stage2.Id,
      data.interviewerA.Id,
      firstBookableStart().addDays(1),
      3
    );

    System.assertEquals(
      1,
      countInterviews(data.application.Id, data.stage2.Id)
    );

    insertNonRecurringAvailability(
      data.stage2.Id,
      data.interviewerA.Id,
      firstBookableStart().addDays(2),
      3
    );

    System.assertEquals(
      1,
      countInterviews(data.application.Id, data.stage2.Id),
      'Adding more Stage 2 availability must not duplicate an existing pending Stage 2 interview.'
    );
  }

  private static DataBundle createLifecycleData(
    Integer numberOfStages,
    Boolean createTeamMembers,
    Boolean createAvailability,
    Boolean recurringAvailability,
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
      'Cand' + seed,
      'Candidate',
      'cand' + seed,
      profileRecord.Id
    );
    data.interviewerA = buildUser(
      'Interviewer' + seed,
      'A',
      'inta' + seed,
      profileRecord.Id
    );

    List<User> usersToInsert = new List<User>{
      data.candidateUser,
      data.interviewerA
    };

    if (secondInterviewer == true) {
      data.interviewerB = buildUser(
        'Interviewer' + seed,
        'B',
        'intb' + seed,
        profileRecord.Id
      );
      usersToInsert.add(data.interviewerB);
    }

    insert as system usersToInsert;

    data.candidate = new Candidate__c(
      FirstName__c = 'Cand' + seed,
      LastName__c = 'Candidate',
      Phone__c = '+2126' + String.valueOf(seed).right(8),
      Email__c = 'candidate.' + seed + '@example.com',
      User__c = data.candidateUser.Id
    );
    insert as system data.candidate;

    data.job = new Job_Position__c(
      Title__c = 'Consultant ' + seed,
      Status__c = 'Draft',
      Portal_Description__c = 'Portal description',
      Detailed_Tasks__c = 'Detailed tasks',
      Evaluation_Criteria__c = 'Evaluation criteria',
      Application_Deadline__c = Date.today().addDays(30),
      Desired_Hires__c = 1,
      Max_Interview_Candidates__c = 10
    );
    insert as system data.job;

    List<Interview_Stage__c> stages = new List<Interview_Stage__c>();

    for (Integer i = 1; i <= numberOfStages; i++) {
      stages.add(
        new Interview_Stage__c(
          Name = 'Stage ' + i + ' ' + seed,
          Job_Position__c = data.job.Id,
          Stage_Number__c = i,
          Duration_Minutes__c = 30,
          Stage_Weight__c = Decimal.valueOf(100) / numberOfStages,
          Max_Score__c = 20,
          Passing_Threshold__c = 12
        )
      );
    }

    insert as system stages;

    data.stage1 = stages[0];

    if (numberOfStages >= 2) {
      data.stage2 = stages[1];
    }

    if (numberOfStages >= 3) {
      data.stage3 = stages[2];
    }

    if (createTeamMembers == true) {
      for (Interview_Stage__c stage : stages) {
        insertTeamMember(stage.Id, data.interviewerA.Id);

        if (secondInterviewer == true) {
          insertTeamMember(stage.Id, data.interviewerB.Id);
        }
      }
    }

    if (createAvailability == true) {
      if (recurringAvailability == true) {
        insertRecurringAvailabilityForAllWeekDays(null, data.interviewerA.Id);

        if (secondInterviewer == true) {
          insertRecurringAvailabilityForAllWeekDays(null, data.interviewerB.Id);
        }
      } else {
        insertNonRecurringAvailability(
          null,
          data.interviewerA.Id,
          firstBookableStart(),
          3
        );

        if (secondInterviewer == true) {
          insertNonRecurringAvailability(
            null,
            data.interviewerB.Id,
            firstBookableStart(),
            3
          );
        }
      }
    }

    data.application = new Job_Application__c(
      Candidate__c = data.candidate.Id,
      Job_Position__c = data.job.Id,
      Stage__c = APP_STAGE_NEW
    );
    insert as system data.application;

    return data;
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

  private static void insertNonRecurringAvailability(
    Id stageId,
    Id interviewerId,
    Datetime startDt,
    Integer hours
  ) {
    insert as system new Availability_Slot__c(
      Interviewer__c = interviewerId,
      Interview_Stage__c = stageId,
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Is_Booked__c = false,
      Day_Of_Week__c = startDt.format('EEEE'),
      Start_DateTime__c = startDt,
      End_DateTime__c = startDt.addHours(hours)
    );
  }

  private static void scheduleAsCandidate(User candidateUser, Id interviewId) {
    System.runAs(candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        interviewId,
        weekStartFor(firstBookableStart())
      );

      System.assert(
        !slots.isEmpty(),
        'Candidate should have at least one valid slot to choose.'
      );

      CandidateInterviewSchedulerCtrl.scheduleInterview(
        interviewId,
        String.valueOf(slots[0].startDt)
      );
    }
  }

  private static void assertScheduled(Id interviewId) {
    Interview__c interviewRecord = [
      SELECT
        Status__c,
        Interviewer__c,
        Scheduled_DateTime__c,
        Availability_Slot__c
      FROM Interview__c
      WHERE Id = :interviewId
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, interviewRecord.Status__c);
    System.assertNotEquals(null, interviewRecord.Interviewer__c);
    System.assertNotEquals(null, interviewRecord.Scheduled_DateTime__c);
    System.assertNotEquals(null, interviewRecord.Availability_Slot__c);
  }

  private static Interview__c getOnlyInterview(Id applicationId, Id stageId) {
    List<Interview__c> interviews = [
      SELECT
        Id,
        Status__c,
        Interviewer__c,
        Scheduled_DateTime__c,
        Scheduling_Deadline__c,
        Availability_Slot__c
      FROM Interview__c
      WHERE
        Job_Application__c = :applicationId
        AND Interview_Stage__c = :stageId
      ORDER BY CreatedDate ASC
    ];

    System.assertEquals(
      1,
      interviews.size(),
      'Exactly one interview should exist for this application and stage.'
    );

    return interviews[0];
  }

  private static Integer countInterviews(Id applicationId, Id stageId) {
    return [
      SELECT COUNT()
      FROM Interview__c
      WHERE
        Job_Application__c = :applicationId
        AND Interview_Stage__c = :stageId
    ];
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
