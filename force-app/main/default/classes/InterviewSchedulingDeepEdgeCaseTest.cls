/**
 * @description Additional end-to-end edge case tests for the TalentForce interview scheduling lifecycle.
 * Covers recurring/non-recurring availability, blocked windows, candidate attempt tracking,
 * deadline batch behavior, stage progression, duplicate protection, and interviewer availability actions.
 */
@IsTest
private class InterviewSchedulingDeepEdgeCaseTest {
  private static final String APP_STAGE_NEW = 'New';
  private static final String APP_STAGE_INTERVIEW = 'Interview';
  private static final String APP_STAGE_WITHDRAWN = 'Withdrawn';

  private static final String STATUS_PENDING = 'Pending_Scheduling';
  private static final String STATUS_SCHEDULED = 'Scheduled';
  private static final String STATUS_CANCELLED = 'Cancelled';

  private static final String ISSUE_NO_AVAILABLE_SLOTS = 'No_Available_Slots';
  private static final String ISSUE_SLOT_BECAME_UNAVAILABLE = 'Slot_Became_Unavailable';

  private class DataBundle {
    User candidateUser;
    User otherCandidateUser;
    User interviewerA;
    User interviewerB;
    Candidate__c candidate;
    Candidate__c otherCandidate;
    Job_Position__c job;
    Interview_Stage__c stage1;
    Interview_Stage__c stage2;
    Interview_Stage__c stage3;
    Job_Application__c application;
    Job_Application__c otherApplication;
  }

  @IsTest
  static void blockedNonRecurringAvailabilityDoesNotCreatePendingInterview() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      true,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    assertInterviewCount(
      data.application.Id,
      data.stage1.Id,
      0,
      'Blocked one-time availability must not create a pending interview.'
    );
  }

  @IsTest
  static void blockedRecurringAvailabilityDoesNotCreatePendingInterview() {
    DataBundle data = createBaseData(1, true, false, false);

    insertRecurringWindow(data.interviewerA.Id, 'Monday', 9, 12, true);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    assertInterviewCount(
      data.application.Id,
      data.stage1.Id,
      0,
      'Blocked recurring availability must not create a pending interview.'
    );
  }

  @IsTest
  static void activeRecurringAvailabilityCreatesPendingInterview() {
    DataBundle data = createBaseData(1, true, false, false);

    insertRecurringWindow(data.interviewerA.Id, 'Monday', 9, 12, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

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
  static void activeNonRecurringAvailabilityCreatesPendingInterview() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );
    System.assertEquals(STATUS_PENDING, pendingInterview.Status__c);
  }

  @IsTest
  static void recurringBlockedForSpecificDateRemovesThatDateFromCandidateSlots() {
    DataBundle data = createBaseData(1, true, false, false);

    Datetime startDt = firstBookableStart();
    String dayName = startDt.format('EEEE');
    insertRecurringWindow(
      data.interviewerA.Id,
      dayName,
      startDt.hour(),
      startDt.hour() + 3,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      true,
      false
    );

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(startDt)
      );

      for (AvailabilitySlotService.TimeSlotDTO slot : slots) {
        System.assert(
          slot.startDt < startDt || slot.startDt >= startDt.addHours(3),
          'Blocked exception must remove overlapping recurring slots for that date.'
        );
      }
    }
  }

  @IsTest
  static void nonRecurringPositiveSlotCanBeScheduledAndMarkedBooked() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();

    Availability_Slot__c sourceSlot = insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        pendingInterview.Id,
        String.valueOf(startDt)
      );
    }

    Interview__c scheduledInterview = [
      SELECT Status__c, Availability_Slot__c, Scheduled_DateTime__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    Availability_Slot__c bookedSourceSlot = [
      SELECT Is_Recurring__c, Is_Booked__c, Booked_Interview__c
      FROM Availability_Slot__c
      WHERE Id = :sourceSlot.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, scheduledInterview.Status__c);
    System.assertEquals(sourceSlot.Id, scheduledInterview.Availability_Slot__c);
    System.assertEquals(false, bookedSourceSlot.Is_Recurring__c);
    System.assertEquals(true, bookedSourceSlot.Is_Booked__c);
    System.assertEquals(
      pendingInterview.Id,
      bookedSourceSlot.Booked_Interview__c
    );
  }

  @IsTest
  static void recurringSlotSchedulingCreatesBookedInstanceAndLeavesWindowReusable() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();
    String dayName = startDt.format('EEEE');

    insertRecurringWindow(
      data.interviewerA.Id,
      dayName,
      startDt.hour(),
      startDt.hour() + 3,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        pendingInterview.Id,
        String.valueOf(startDt)
      );
    }

    Interview__c scheduledInterview = [
      SELECT Id, Status__c, Availability_Slot__c, Interviewer__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    Availability_Slot__c bookedInstance = [
      SELECT Is_Recurring__c, Is_Booked__c, Booked_Interview__c, Interviewer__c
      FROM Availability_Slot__c
      WHERE Id = :scheduledInterview.Availability_Slot__c
      LIMIT 1
    ];

    Integer bookedRecurringWindows = [
      SELECT COUNT()
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :data.interviewerA.Id
        AND Is_Recurring__c = TRUE
        AND Is_Booked__c = TRUE
    ];

    System.assertEquals(STATUS_SCHEDULED, scheduledInterview.Status__c);
    System.assertEquals(false, bookedInstance.Is_Recurring__c);
    System.assertEquals(true, bookedInstance.Is_Booked__c);
    System.assertEquals(
      scheduledInterview.Id,
      bookedInstance.Booked_Interview__c
    );
    System.assertEquals(data.interviewerA.Id, bookedInstance.Interviewer__c);
    System.assertEquals(
      0,
      bookedRecurringWindows,
      'Recurring windows are definitions and must not be booked directly.'
    );
  }

  @IsTest
  static void candidateNoAvailableSlotsIssueMarksAttemptAndPreventsWithdrawal() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.recordNoAvailableSlots(
        pendingInterview.Id
      );
    }

    Interview__c attemptedInterview = [
      SELECT
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      attemptedInterview.Candidate_Tried_To_Schedule__c
    );
    System.assertNotEquals(
      null,
      attemptedInterview.Candidate_Tried_To_Schedule_At__c
    );
    System.assertEquals(
      ISSUE_NO_AVAILABLE_SLOTS,
      attemptedInterview.Scheduling_Issue_Reason__c
    );

    expireInterview(pendingInterview.Id);

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    assertApplicationStage(
      data.application.Id,
      APP_STAGE_INTERVIEW,
      'Candidate should not be withdrawn after a no-available-slots attempt.'
    );
    assertInterviewStatus(pendingInterview.Id, STATUS_PENDING);
  }

  @IsTest
  static void slotBecameUnavailableIssuePreservesExistingAttemptAndPreventsWithdrawal() {
    DataBundle data = createBaseData(1, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.markCandidateTriedToSchedule(
        pendingInterview.Id
      );
      CandidateInterviewSchedulerCtrl.recordSlotBecameUnavailable(
        pendingInterview.Id
      );
    }

    Interview__c attemptedInterview = [
      SELECT
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(
      true,
      attemptedInterview.Candidate_Tried_To_Schedule__c
    );
    System.assertNotEquals(
      null,
      attemptedInterview.Candidate_Tried_To_Schedule_At__c
    );
    System.assertEquals(
      ISSUE_SLOT_BECAME_UNAVAILABLE,
      attemptedInterview.Scheduling_Issue_Reason__c
    );

    expireInterview(pendingInterview.Id);

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    assertApplicationStage(
      data.application.Id,
      APP_STAGE_INTERVIEW,
      'Candidate should not be withdrawn when an attempt already exists.'
    );
    assertInterviewStatus(pendingInterview.Id, STATUS_PENDING);
  }

  @IsTest
  static void successfulSchedulingClearsPreviousSchedulingIssueReason() {
    DataBundle data = createBaseData(1, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.recordNoAvailableSlots(
        pendingInterview.Id
      );
      List<AvailabilitySlotService.TimeSlotDTO> slots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(firstBookableStart())
      );
      System.assert(
        !slots.isEmpty(),
        'A valid slot should exist before scheduling.'
      );
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        pendingInterview.Id,
        String.valueOf(slots[0].startDt)
      );
    }

    Interview__c scheduledInterview = [
      SELECT
        Status__c,
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, scheduledInterview.Status__c);
    System.assertEquals(
      true,
      scheduledInterview.Candidate_Tried_To_Schedule__c
    );
    System.assertNotEquals(
      null,
      scheduledInterview.Candidate_Tried_To_Schedule_At__c
    );
    System.assertEquals(null, scheduledInterview.Scheduling_Issue_Reason__c);
  }

  @IsTest
  static void expiredPendingInterviewWithoutAttemptIsWithdrawnWhenHistoricalSlotsExisted() {
    DataBundle data = createBaseData(1, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    expireInterview(pendingInterview.Id);

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    assertInterviewStatus(pendingInterview.Id, STATUS_CANCELLED);
    assertApplicationStage(
      data.application.Id,
      APP_STAGE_WITHDRAWN,
      'Application should be withdrawn after inactivity.'
    );
  }

  @IsTest
  static void expiredPendingInterviewWithoutHistoricalSlotsIsNotWithdrawn() {
    DataBundle data = createBaseData(1, true, false, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c manualInterview = new Interview__c(
      Job_Application__c = data.application.Id,
      Interview_Stage__c = data.stage1.Id,
      Status__c = STATUS_PENDING,
      Scheduling_Deadline__c = System.now().addDays(-2)
    );
    insert as system manualInterview;
    Test.setCreatedDate(manualInterview.Id, System.now().addDays(-10));

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    assertInterviewStatus(manualInterview.Id, STATUS_PENDING);
    assertApplicationStage(
      data.application.Id,
      APP_STAGE_INTERVIEW,
      'Application should remain Interview when no slots ever existed.'
    );
  }

  @IsTest
  static void stageProgressionWaitsForAvailabilityThenCreatesOnlyOnePendingInterview() {
    DataBundle data = createBaseData(2, true, false, false);
    Datetime stage1Start = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      stage1Start,
      stage1Start.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        stage1Interview.Id,
        String.valueOf(stage1Start)
      );
    }

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      0,
      'Stage 2 must wait for availability.'
    );

    insertAvailability(
      data.interviewerA.Id,
      stage1Start.addDays(1),
      stage1Start.addDays(1).addHours(3),
      false,
      false,
      false
    );

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      1,
      'Stage 2 pending interview should be created once availability exists.'
    );

    insertAvailability(
      data.interviewerA.Id,
      stage1Start.addDays(2),
      stage1Start.addDays(2).addHours(3),
      false,
      false,
      false
    );

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      1,
      'Additional availability must not duplicate the pending stage interview.'
    );
  }

  @IsTest
  static void stageProgressionWaitsForTeamMemberThenRetriesWhenTeamAndAvailabilityExist() {
    DataBundle data = createBaseData(2, false, false, false);
    Datetime startDt = firstBookableStart();

    insertTeamMember(data.stage1.Id, data.interviewerA.Id);
    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        stage1Interview.Id,
        String.valueOf(startDt)
      );
    }

    update as system new Job_Application__c(
      Id = data.application.Id,
      Current_Interview_Stage__c = data.stage2.Id
    );

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      0,
      'Stage 2 must wait for team member.'
    );

    insertAvailability(
      data.interviewerA.Id,
      startDt.addDays(1),
      startDt.addDays(1).addHours(3),
      false,
      false,
      false
    );

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      0,
      'Availability alone must not create Stage 2 interview without team member.'
    );

    insertTeamMember(data.stage2.Id, data.interviewerA.Id);

    assertInterviewCount(
      data.application.Id,
      data.stage2.Id,
      1,
      'Adding the team member should retry waiting applications.'
    );
  }

  @IsTest
  static void candidateCannotSeeOrScheduleAnotherCandidateInterview() {
    DataBundle data = createBaseData(1, true, true, true);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    data.otherApplication.Stage__c = APP_STAGE_INTERVIEW;
    update as system new List<Job_Application__c>{
      data.application,
      data.otherApplication
    };

    Interview__c otherInterview = getOnlyInterview(
      data.otherApplication.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      Boolean failed = false;
      try {
        CandidateInterviewSchedulerCtrl.getAvailableSlots(
          otherInterview.Id,
          weekStartFor(firstBookableStart())
        );
      } catch (AuraHandledException expectedException) {
        failed = true;
      }
      System.assert(
        failed,
        'Candidate must not access another candidate interview.'
      );
    }
  }

  @IsTest
  static void candidateOverlapBlocksSecondInterviewAtSameTime() {
    DataBundle data = createBaseData(2, true, false, false);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );
    insertAvailability(
      data.interviewerA.Id,
      startDt.addDays(1),
      startDt.addDays(1).addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c stage1Interview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    insert as system new Interview__c(
      Job_Application__c = data.application.Id,
      Interview_Stage__c = data.stage2.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = startDt,
      Scheduling_Deadline__c = System.now().addDays(7)
    );

    System.runAs(data.candidateUser) {
      Boolean failed = false;
      try {
        CandidateInterviewSchedulerCtrl.scheduleInterview(
          stage1Interview.Id,
          String.valueOf(startDt)
        );
      } catch (AuraHandledException expectedException) {
        failed = true;
      }
      System.assert(
        failed,
        'Candidate must not schedule overlapping interviews.'
      );
    }
  }

  @IsTest
  static void sameTimeMultipleInterviewersUsesAlternativeWhenOneIsBooked() {
    DataBundle data = createBaseData(1, true, false, true);
    insertTeamMember(data.stage1.Id, data.interviewerB.Id);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );
    insertAvailability(
      data.interviewerB.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    insert as system new Interview__c(
      Job_Application__c = data.otherApplication.Id,
      Interview_Stage__c = data.stage1.Id,
      Interviewer__c = data.interviewerA.Id,
      Status__c = STATUS_SCHEDULED,
      Scheduled_DateTime__c = startDt,
      Scheduling_Deadline__c = System.now().addDays(7)
    );

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    System.runAs(data.candidateUser) {
      CandidateInterviewSchedulerCtrl.scheduleInterview(
        pendingInterview.Id,
        String.valueOf(startDt)
      );
    }

    Interview__c scheduledInterview = [
      SELECT Interviewer__c, Status__c
      FROM Interview__c
      WHERE Id = :pendingInterview.Id
      LIMIT 1
    ];

    System.assertEquals(STATUS_SCHEDULED, scheduledInterview.Status__c);
    System.assertEquals(
      data.interviewerB.Id,
      scheduledInterview.Interviewer__c,
      'If interviewer A is already booked, scheduler should use another eligible interviewer.'
    );
  }

  @IsTest
  static void interviewerControllerBlockAndUnblockRecurringWindowAffectsCandidateSlots() {
    DataBundle data = createBaseData(1, false, false, false);
    Id currentInterviewerId = UserInfo.getUserId();
    insertTeamMember(data.stage1.Id, currentInterviewerId);

    Datetime startDt = firstBookableStart();
    String dayName = startDt.format('EEEE');

    Availability_Slot__c recurring = insertRecurringWindow(
      currentInterviewerId,
      dayName,
      startDt.hour(),
      startDt.hour() + 3,
      false
    );

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c pendingInterview = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    InterviewerAvailabilityController.blockWindowForDate(
      recurring.Id,
      String.valueOf(startDt.date())
    );

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> blockedSlots = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(startDt)
      );
      for (AvailabilitySlotService.TimeSlotDTO slot : blockedSlots) {
        System.assert(
          slot.startDt < startDt || slot.startDt >= startDt.addHours(3),
          'Blocking a recurring date should remove that date from candidate-facing slots.'
        );
      }
    }

    InterviewerAvailabilityController.unblockWindowForDate(
      recurring.Id,
      String.valueOf(startDt.date())
    );

    System.runAs(data.candidateUser) {
      List<AvailabilitySlotService.TimeSlotDTO> availableAgain = CandidateInterviewSchedulerCtrl.getAvailableSlots(
        pendingInterview.Id,
        weekStartFor(startDt)
      );
      System.assert(
        !availableAgain.isEmpty(),
        'Unblocking should make the recurring window available again.'
      );
    }
  }

  @IsTest
  static void interviewerControllerGetMyWindowsReturnsRecurringAndOneTimeButNotDeactivated() {
    Id currentInterviewerId = UserInfo.getUserId();
    Date monday = mondayOf(Date.today().addDays(7));
    Datetime oneTimeStart = Datetime.newInstanceGmt(
      monday.addDays(1),
      Time.newInstance(14, 0, 0, 0)
    );

    insert as system new Availability_Slot__c(
      Interviewer__c = currentInterviewerId,
      Day_Of_Week__c = 'Monday',
      Start_DateTime__c = Datetime.newInstance(
        Date.newInstance(2000, 1, 3),
        Time.newInstance(9, 0, 0, 0)
      ),
      End_DateTime__c = Datetime.newInstance(
        Date.newInstance(2000, 1, 3),
        Time.newInstance(12, 0, 0, 0)
      ),
      Is_Recurring__c = true,
      Is_Blocked__c = false,
      Effective_From__c = monday
    );

    insert as system new Availability_Slot__c(
      Interviewer__c = currentInterviewerId,
      Day_Of_Week__c = 'Tuesday',
      Start_DateTime__c = oneTimeStart,
      End_DateTime__c = oneTimeStart.addHours(2),
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Deactivated_Date__c = null
    );

    insert as system new Availability_Slot__c(
      Interviewer__c = currentInterviewerId,
      Day_Of_Week__c = 'Wednesday',
      Start_DateTime__c = oneTimeStart.addDays(1),
      End_DateTime__c = oneTimeStart.addDays(1).addHours(2),
      Is_Recurring__c = false,
      Is_Blocked__c = false,
      Deactivated_Date__c = Date.today()
    );

    List<Availability_Slot__c> windows = InterviewerAvailabilityController.getMyWindows(
      String.valueOf(monday)
    );
    System.assertEquals(
      2,
      windows.size(),
      'Should include active recurring and active one-time only.'
    );
  }

  @IsTest
  static void interviewerControllerSaveRecurringWindowDeactivatesOverlappingOneTimeSlots() {
    Id currentInterviewerId = UserInfo.getUserId();
    Date monday = mondayOf(Date.today().addDays(7));
    Datetime mondayOneTime = Datetime.newInstanceGmt(
      monday,
      Time.newInstance(10, 0, 0, 0)
    );

    Availability_Slot__c oneTimeSlot = insertAvailability(
      currentInterviewerId,
      mondayOneTime,
      mondayOneTime.addHours(1),
      false,
      false,
      false
    );

    InterviewerAvailabilityController.saveWindow(
      'Monday',
      '09:00',
      '12:00',
      String.valueOf(monday),
      true
    );

    Availability_Slot__c refreshedOneTime = [
      SELECT Deactivated_Date__c
      FROM Availability_Slot__c
      WHERE Id = :oneTimeSlot.Id
      LIMIT 1
    ];

    System.assertNotEquals(
      null,
      refreshedOneTime.Deactivated_Date__c,
      'A new recurring window should deactivate overlapping one-time positive windows.'
    );
  }

  @IsTest
  static void interviewerControllerSaveOneTimeWindowFailsWhenRecurringAlreadyCoversIt() {
    Id currentInterviewerId = UserInfo.getUserId();
    Date monday = mondayOf(Date.today().addDays(7));

    insertRecurringWindow(currentInterviewerId, 'Monday', 9, 12, false);

    Boolean failed = false;
    try {
      InterviewerAvailabilityController.saveWindow(
        'Monday',
        '10:00',
        '11:00',
        String.valueOf(monday),
        false
      );
    } catch (AuraHandledException expectedException) {
      failed = true;
    }
    System.assert(
      failed,
      'One-time availability should fail if an active recurring window already covers it.'
    );
  }

  @IsTest
  static void availabilityTriggerBlocksOverlappingPositiveSlotsButAllowsBookedInsideRecurringWindow() {
    DataBundle data = createBaseData(1, true, false, false);
    Datetime startDt = firstBookableStart();

    insertAvailability(
      data.interviewerA.Id,
      startDt,
      startDt.addHours(3),
      false,
      false,
      false
    );

    Boolean overlappingPositiveFailed = false;
    try {
      insertAvailability(
        data.interviewerA.Id,
        startDt.addMinutes(30),
        startDt.addHours(2),
        false,
        false,
        false
      );
    } catch (DmlException expectedException) {
      overlappingPositiveFailed = true;
    }
    System.assert(
      overlappingPositiveFailed,
      'Availability trigger must block overlapping positive windows.'
    );

    insertRecurringWindow(
      data.interviewerB.Id,
      startDt.format('EEEE'),
      startDt.hour(),
      startDt.hour() + 3,
      false
    );
    insertAvailability(
      data.interviewerB.Id,
      startDt,
      startDt.addMinutes(30),
      false,
      false,
      true
    );

    Integer bookedInstances = [
      SELECT COUNT()
      FROM Availability_Slot__c
      WHERE Interviewer__c = :data.interviewerB.Id AND Is_Booked__c = TRUE
    ];
    System.assertEquals(
      1,
      bookedInstances,
      'Booked instance should be allowed inside its recurring parent window.'
    );
  }

  @IsTest
  static void completedAndCancelledInterviewsAreIgnoredByDeadlineBatch() {
    DataBundle data = createBaseData(1, true, true, false);

    data.application.Stage__c = APP_STAGE_INTERVIEW;
    update as system data.application;

    Interview__c interviewRecord = getOnlyInterview(
      data.application.Id,
      data.stage1.Id
    );

    update as system new Interview__c(
      Id = interviewRecord.Id,
      Status__c = STATUS_CANCELLED,
      Scheduling_Deadline__c = System.now().addDays(-2)
    );

    Test.startTest();
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 50);
    Test.stopTest();

    assertApplicationStage(
      data.application.Id,
      APP_STAGE_INTERVIEW,
      'Cancelled interview should not withdraw again.'
    );
    assertInterviewStatus(interviewRecord.Id, STATUS_CANCELLED);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Test data helpers
  // ────────────────────────────────────────────────────────────────────────

  private static DataBundle createBaseData(
    Integer numberOfStages,
    Boolean createTeamMembers,
    Boolean createAvailability,
    Boolean createOtherCandidate
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
    data.interviewerB = buildUser(
      'Interviewer' + seed,
      'B',
      'intb' + seed,
      profileRecord.Id
    );

    List<User> usersToInsert = new List<User>{
      data.candidateUser,
      data.interviewerA,
      data.interviewerB
    };

    if (createOtherCandidate == true) {
      data.otherCandidateUser = buildUser(
        'Other' + seed,
        'Candidate',
        'othc' + seed,
        profileRecord.Id
      );
      usersToInsert.add(data.otherCandidateUser);
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

    if (createOtherCandidate == true) {
      data.otherCandidate = new Candidate__c(
        FirstName__c = 'Other' + seed,
        LastName__c = 'Candidate',
        Phone__c = '+2127' + String.valueOf(seed).right(8),
        Email__c = 'other.candidate.' + seed + '@example.com',
        User__c = data.otherCandidateUser.Id
      );
      insert as system data.otherCandidate;
    }

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
      for (Interview_Stage__c stageRecord : stages) {
        insertTeamMember(stageRecord.Id, data.interviewerA.Id);
      }
    }

    if (createAvailability == true) {
      Datetime startDt = firstBookableStart();
      insertAvailability(
        data.interviewerA.Id,
        startDt,
        startDt.addHours(3),
        false,
        false,
        false
      );
    }

    data.application = new Job_Application__c(
      Candidate__c = data.candidate.Id,
      Job_Position__c = data.job.Id,
      Stage__c = APP_STAGE_NEW
    );
    insert as system data.application;

    if (createOtherCandidate == true) {
      data.otherApplication = new Job_Application__c(
        Candidate__c = data.otherCandidate.Id,
        Job_Position__c = data.job.Id,
        Stage__c = APP_STAGE_NEW
      );
      insert as system data.otherApplication;
    }

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

  private static Availability_Slot__c insertRecurringWindow(
    Id interviewerId,
    String dayOfWeek,
    Integer startHour,
    Integer endHour,
    Boolean blocked
  ) {
    Date baseDate = Date.newInstance(2000, 1, 3).addDays(dayOffset(dayOfWeek));
    Availability_Slot__c slot = new Availability_Slot__c(
      Interviewer__c = interviewerId,
      Day_Of_Week__c = dayOfWeek,
      Start_DateTime__c = Datetime.newInstance(
        baseDate,
        Time.newInstance(startHour, 0, 0, 0)
      ),
      End_DateTime__c = Datetime.newInstance(
        baseDate,
        Time.newInstance(endHour, 0, 0, 0)
      ),
      Is_Recurring__c = true,
      Is_Blocked__c = blocked,
      Is_Booked__c = false
    );
    insert as system slot;
    return slot;
  }

  private static Availability_Slot__c insertAvailability(
    Id interviewerId,
    Datetime startDt,
    Datetime endDt,
    Boolean recurring,
    Boolean blocked,
    Boolean booked
  ) {
    Availability_Slot__c slot = new Availability_Slot__c(
      Interviewer__c = interviewerId,
      Day_Of_Week__c = startDt.format('EEEE'),
      Start_DateTime__c = startDt,
      End_DateTime__c = endDt,
      Is_Recurring__c = recurring,
      Is_Blocked__c = blocked,
      Is_Booked__c = booked
    );
    insert as system slot;
    return slot;
  }

  private static void expireInterview(Id interviewId) {
    Test.setCreatedDate(interviewId, System.now().addDays(-10));
    update as system new Interview__c(
      Id = interviewId,
      Scheduling_Deadline__c = System.now().addDays(-2)
    );
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

  private static void assertInterviewCount(
    Id applicationId,
    Id stageId,
    Integer expectedCount,
    String message
  ) {
    Integer actualCount = [
      SELECT COUNT()
      FROM Interview__c
      WHERE
        Job_Application__c = :applicationId
        AND Interview_Stage__c = :stageId
    ];
    System.assertEquals(expectedCount, actualCount, message);
  }

  private static void assertInterviewStatus(
    Id interviewId,
    String expectedStatus
  ) {
    Interview__c interviewRecord = [
      SELECT Status__c
      FROM Interview__c
      WHERE Id = :interviewId
      LIMIT 1
    ];
    System.assertEquals(expectedStatus, interviewRecord.Status__c);
  }

  private static void assertApplicationStage(
    Id applicationId,
    String expectedStage,
    String message
  ) {
    Job_Application__c applicationRecord = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      LIMIT 1
    ];
    System.assertEquals(expectedStage, applicationRecord.Stage__c, message);
  }

  private static Datetime firstBookableStart() {
    return Datetime.newInstance(
      Date.today().addDays(5),
      Time.newInstance(9, 0, 0, 0)
    );
  }

  private static Date mondayOf(Date inputDate) {
    Date baseMonday = Date.newInstance(1900, 1, 1);
    Integer offset = Math.mod(baseMonday.daysBetween(inputDate), 7);
    if (offset < 0) {
      offset += 7;
    }
    return inputDate.addDays(-offset);
  }

  private static String weekStartFor(Datetime value) {
    return String.valueOf(mondayOf(value.date()));
  }

  private static Integer dayOffset(String dayName) {
    Map<String, Integer> offsets = new Map<String, Integer>{
      'Monday' => 0,
      'Tuesday' => 1,
      'Wednesday' => 2,
      'Thursday' => 3,
      'Friday' => 4,
      'Saturday' => 5,
      'Sunday' => 6
    };
    return offsets.containsKey(dayName) ? offsets.get(dayName) : 0;
  }

  private static Long uniqueSeed() {
    return System.currentTimeMillis() +
      Limits.getDmlRows() +
      Math.abs(Crypto.getRandomInteger());
  }
}
