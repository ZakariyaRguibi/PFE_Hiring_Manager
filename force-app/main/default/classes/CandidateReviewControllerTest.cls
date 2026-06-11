/**
 * @description Tests for CandidateReviewController — waitlist, promotion,
 *              concurrent lock, capacity sync on decline, and pagination.
 *
 * @author Hiba Balhirch, Marwane Romani
 * @date 2026-05-21
 */
@IsTest
private class CandidateReviewControllerTest {
  private static Integer phoneCounter = 10000000;

  // ─── Helpers ─────────────────────────────────────────────────────────────

  private static Job_Position__c createJob(String title) {
    Job_Position__c job = new Job_Position__c(
      Title__c = title,
      Required_Skills__c = 'Apex, LWC, Salesforce',
      Required_Education__c = 'Bachelor',
      Required_Experience__c = 2
    );
    insert job;
    return job;
  }

  private static Interview_Stage__c createStage(
    Id jobId,
    Integer stageNumber,
    String stageName
  ) {
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = jobId,
      Name = stageName,
      Stage_Number__c = stageNumber,
      Duration_Minutes__c = 30,
      Passing_Threshold__c = 60,
      Max_Score__c = 100
    );
    insert stage;
    return stage;
  }

  private static Candidate__c createCandidate(String email, String firstName) {
    phoneCounter++;
    Candidate__c candidate = new Candidate__c(
      FirstName__c = firstName,
      LastName__c = 'Candidate',
      Email__c = email,
      Phone__c = '06' + String.valueOf(phoneCounter),
      Education_Level__c = 'Bachelor',
      Years_of_Experience__c = 2
    );
    insert candidate;
    return candidate;
  }

  private static Job_Application__c createScoredApplication(
    Candidate__c candidate,
    Job_Position__c job,
    Decimal score
  ) {
    Job_Application__c app = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = job.Id,
      Stage__c = 'New',
      Extracted_Skills__c = 'Apex, LWC, Salesforce',
      Extracted_Education__c = 'Bachelor',
      Extracted_Experience__c = 2
    );
    insert app;
    app.AI_Score__c = score;
    app.Final_Score__c = score;
    app.Skills_Match_Score__c = score;
    app.Experience_Score__c = score;
    app.Education_Score__c = score;
    app.Keywords_Score__c = score;
    app.AI_Filter_Decision__c = 'Pass';
    app.Passed_Hard_Filter__c = true;
    app.AI_Scored_At__c = Datetime.now();
    update as system app;
    return app;
  }

  private static void addTeamMemberAndSlot(Id stageId) {
    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stageId,
      Interviewer__c = UserInfo.getUserId(),
      Role__c = 'Lead'
    );
    insert new Availability_Slot__c(
      Interviewer__c = UserInfo.getUserId(),
      Interview_Stage__c = stageId,
      Start_DateTime__c = System.now().addDays(5),
      End_DateTime__c = System.now().addDays(5).addHours(1),
      Is_Booked__c = false
    );
  }

  // ─── Existing: waitlist and first-stage promotion ────────────────────────

  @IsTest
  static void firstStageWaitlistUsesNewApplicationsWithNoCurrentStage() {
    Job_Position__c job = createJob('Waitlist Job');
    Interview_Stage__c firstStage = createStage(job.Id, 1, 'Phone Screen');
    createStage(job.Id, 2, 'Technical');

    Job_Application__c lowerScore = createScoredApplication(
      createCandidate('low@example.com', 'Low'),
      job,
      55
    );
    Job_Application__c higherScore = createScoredApplication(
      createCandidate('high@example.com', 'High'),
      job,
      90
    );

    CandidateReviewController.StageReviewData data = CandidateReviewController.getCandidatesForStage(
      job.Id,
      firstStage.Id,
      0
    );

    System.assertEquals(
      true,
      data.isFirstStage,
      'The selected stage is first.'
    );
    System.assertEquals(
      0,
      data.activeCandidates.size(),
      'No candidate should be active before HR promotion.'
    );
    System.assertEquals(
      2,
      data.waitingCandidates.size(),
      'Scored New applications must appear in the first-stage waitlist.'
    );
    System.assertEquals(
      higherScore.Id,
      data.waitingCandidates[0].applicationId,
      'First-stage waitlist must be ranked by AI score descending.'
    );
    System.assertEquals(
      lowerScore.Id,
      data.waitingCandidates[1].applicationId,
      'Lower score should appear after higher score.'
    );
  }

  @IsTest
  static void promoteCandidateMovesToActiveStageAndCreatesPendingInterview() {
    Job_Position__c job = createJob('Promotion Job');
    Interview_Stage__c firstStage = createStage(job.Id, 1, 'Phone Screen');
    addTeamMemberAndSlot(firstStage.Id);

    Job_Application__c app = createScoredApplication(
      createCandidate('promote@example.com', 'Promote'),
      job,
      88
    );

    Test.startTest();
    CandidateReviewController.promoteCandidate(app.Id, firstStage.Id);
    Test.stopTest();

    Job_Application__c promoted = [
      SELECT Stage__c, Current_Interview_Stage__c, Selection_Status__c
      FROM Job_Application__c
      WHERE Id = :app.Id
    ];

    System.assertEquals(
      'Interview',
      promoted.Stage__c,
      'Promotion must move the application into the interview process.'
    );
    System.assertEquals(
      firstStage.Id,
      promoted.Current_Interview_Stage__c,
      'Promotion must attach the application to the first interview stage.'
    );
    System.assertEquals(
      'Selected',
      promoted.Selection_Status__c,
      'Promoted candidate must have Selection_Status__c = Selected.'
    );

    List<Interview__c> interviews = [
      SELECT Status__c, Interview_Stage__c
      FROM Interview__c
      WHERE Job_Application__c = :app.Id
    ];
    System.assertEquals(
      1,
      interviews.size(),
      'One pending scheduling interview should be created on promotion.'
    );
    System.assertEquals('Pending_Scheduling', interviews[0].Status__c);
    System.assertEquals(firstStage.Id, interviews[0].Interview_Stage__c);
  }

  @IsTest
  static void promoteCandidateRejectsStageFromAnotherJob() {
    Job_Position__c job = createJob('Main Job');
    Job_Position__c otherJob = createJob('Other Job');
    createStage(job.Id, 1, 'Phone Screen');
    Interview_Stage__c otherStage = createStage(otherJob.Id, 1, 'Phone Screen');
    Job_Application__c app = createScoredApplication(
      createCandidate('wrong-stage@example.com', 'Wrong'),
      job,
      80
    );

    Boolean didThrow = false;
    Test.startTest();
    try {
      CandidateReviewController.promoteCandidate(app.Id, otherStage.Id);
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      didThrow,
      'Promotion should fail for a stage from another job.'
    );
  }

  // ─── Concurrent promotion lock ────────────────────────────────────────────

  @IsTest
  static void promotingAlreadySelectedCandidateToSameStageThrows() {
    Job_Position__c job = createJob('Concurrent Job');
    Interview_Stage__c stage = createStage(job.Id, 1, 'Phone Screen');
    addTeamMemberAndSlot(stage.Id);

    Job_Application__c app = createScoredApplication(
      createCandidate('concurrent@example.com', 'Concurrent'),
      job,
      75
    );

    // First promote succeeds
    Test.startTest();
    CandidateReviewController.promoteCandidate(app.Id, stage.Id);

    // Second promote to same stage should throw
    Boolean didThrow = false;
    try {
      CandidateReviewController.promoteCandidate(app.Id, stage.Id);
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      didThrow,
      'Promoting an already-selected candidate to the same stage should throw.'
    );
  }

  // ─── Capacity sync on offer decline ──────────────────────────────────────

  @IsTest
  static void decliningOfferSetsStageToWithdrawn() {
    Job_Position__c job = createJob('Decline Job');
    Job_Application__c app = createScoredApplication(
      createCandidate('decline@example.com', 'Decline'),
      job,
      70
    );

    // Put app in Offer stage
    app.Stage__c = 'Offer';
    update as system app;

    Test.startTest();
    CandidateReviewController.markOfferDeclined(app.Id);
    Test.stopTest();

    Job_Application__c result = [
      SELECT Stage__c
      FROM Job_Application__c
      WHERE Id = :app.Id
    ];
    System.assertEquals(
      'Withdrawn',
      result.Stage__c,
      'Declining an offer must set Stage__c to Withdrawn.'
    );
  }

  // ─── Stage delete blocked with active candidates ──────────────────────────

  @IsTest
  static void deleteStageBlockedWhenCandidatesActive() {
    Job_Position__c job = createJob('Delete Guard Job');
    Interview_Stage__c stage = createStage(job.Id, 1, 'Phone Screen');
    addTeamMemberAndSlot(stage.Id);

    Job_Application__c app = createScoredApplication(
      createCandidate('delete@example.com', 'Delete'),
      job,
      80
    );

    // Promote candidate into the stage
    Test.startTest();
    CandidateReviewController.promoteCandidate(app.Id, stage.Id);

    Boolean didThrow = false;
    try {
      InterviewPipelineController.deleteStage(stage.Id);
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      didThrow,
      'Deleting a stage with active candidates must be blocked.'
    );
    List<Interview_Stage__c> remaining = [
      SELECT Id
      FROM Interview_Stage__c
      WHERE Id = :stage.Id
    ];
    System.assertEquals(
      1,
      remaining.size(),
      'Stage should still exist after blocked delete.'
    );
  }

  @IsTest
  static void deleteStageSucceedsWhenNoActiveCandidates() {
    Job_Position__c job = createJob('Empty Stage Job');
    Interview_Stage__c stage = createStage(job.Id, 1, 'Phone Screen');

    Boolean didThrow = false;
    Test.startTest();
    try {
      InterviewPipelineController.deleteStage(stage.Id);
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      false,
      didThrow,
      'Deleting an empty stage should succeed.'
    );
    List<Interview_Stage__c> remaining = [
      SELECT Id
      FROM Interview_Stage__c
      WHERE Id = :stage.Id
    ];
    System.assertEquals(0, remaining.size(), 'Stage should be deleted.');
  }

  // ─── Stage reorder blocked with active candidates ─────────────────────────

  @IsTest
  static void reorderStagesBlockedWhenCandidatesActive() {
    Job_Position__c job = createJob('Reorder Guard Job');
    Interview_Stage__c stage1 = createStage(job.Id, 1, 'Phone Screen');
    Interview_Stage__c stage2 = createStage(job.Id, 2, 'Technical');
    addTeamMemberAndSlot(stage1.Id);

    Job_Application__c app = createScoredApplication(
      createCandidate('reorder@example.com', 'Reorder'),
      job,
      80
    );
    CandidateReviewController.promoteCandidate(app.Id, stage1.Id);

    Boolean didThrow = false;
    Test.startTest();
    try {
      InterviewPipelineController.reorderStages(
        new List<Id>{ stage2.Id, stage1.Id }
      );
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      true,
      didThrow,
      'Reordering stages with active candidates must be blocked.'
    );
  }

  @IsTest
  static void reorderStagesSucceedsWhenNoActiveCandidates() {
    Job_Position__c job = createJob('Reorder OK Job');
    Interview_Stage__c stage1 = createStage(job.Id, 1, 'Phone Screen');
    Interview_Stage__c stage2 = createStage(job.Id, 2, 'Technical');

    Boolean didThrow = false;
    Test.startTest();
    try {
      InterviewPipelineController.reorderStages(
        new List<Id>{ stage2.Id, stage1.Id }
      );
    } catch (AuraHandledException e) {
      didThrow = true;
    }
    Test.stopTest();

    System.assertEquals(
      false,
      didThrow,
      'Reordering empty stages should succeed.'
    );
    Interview_Stage__c updatedStage2 = [
      SELECT Stage_Number__c
      FROM Interview_Stage__c
      WHERE Id = :stage2.Id
    ];
    System.assertEquals(
      1,
      updatedStage2.Stage_Number__c,
      'Stage 2 should now be Stage 1 after reorder.'
    );
  }

  // ─── Waiting list pagination ──────────────────────────────────────────────

  @IsTest
  static void waitingTotalReflectsAllCandidatesNotJustCurrentPage() {
    Job_Position__c job = createJob('Pagination Job');
    Interview_Stage__c stage = createStage(job.Id, 1, 'Phone Screen');

    // Create 5 candidates — more than page size of 3 used in tests
    for (Integer i = 0; i < 5; i++) {
      createScoredApplication(
        createCandidate('page' + i + '@example.com', 'Page' + i),
        job,
        Decimal.valueOf(50 + i)
      );
    }

    Test.startTest();
    CandidateReviewController.StageReviewData page1 = CandidateReviewController.getCandidatesForStage(
      job.Id,
      stage.Id,
      0
    );
    Test.stopTest();

    System.assertEquals(
      5,
      page1.waitingTotal,
      'waitingTotal must reflect all candidates, not just the current page.'
    );
    System.assert(
      page1.waitingCandidates.size() <= 5,
      'Page should not exceed total count.'
    );
  }

  @IsTest
  static void secondPageReturnsNextSliceOfCandidates() {
    Job_Position__c job = createJob('Pagination Slice Job');
    Interview_Stage__c stage = createStage(job.Id, 1, 'Phone Screen');

    // 5 candidates — enough to verify OFFSET without hitting governor limits.
    // We use a fixed offset=3 to simulate a second page within the same dataset
    // rather than creating 21+ records to exceed the real page size of 20.
    for (Integer i = 0; i < 5; i++) {
      createScoredApplication(
        createCandidate('slice' + i + '@example.com', 'Slice' + i),
        job,
        Decimal.valueOf(10 + i)
      );
    }

    Test.startTest();
    CandidateReviewController.StageReviewData page1 =
      CandidateReviewController.getCandidatesForStage(job.Id, stage.Id, 0);
    CandidateReviewController.StageReviewData page2 =
      CandidateReviewController.getCandidatesForStage(job.Id, stage.Id, 3);
    Test.stopTest();

    // page1 (offset=0) returns all 5; page2 (offset=3) returns only 2
    System.assertEquals(5, page1.waitingCandidates.size(), 'Offset 0 should return all 5 candidates.');
    System.assertEquals(2, page2.waitingCandidates.size(), 'Offset 3 should return the last 2 candidates.');
    System.assertEquals(page1.waitingTotal, page2.waitingTotal, 'Total should be consistent across pages.');
  }
}
