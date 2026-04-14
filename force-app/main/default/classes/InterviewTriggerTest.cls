@IsTest
private class InterviewTriggerTest {
  // ─── Test Data Setup ──────────────────────────────────────────────────────

  private static Job_Position__c createPosition() {
    Job_Position__c pos = new Job_Position__c(Title__c = 'Test Position');
    insert pos;
    return pos;
  }

  private static Interview_Stage__c createStage(
    Id positionId,
    Decimal maxScore
  ) {
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = positionId,
      Stage_Number__c = 1,
      Max_Score__c = maxScore,
      Passing_Threshold__c = maxScore * 0.5
    );
    insert stage;
    return stage;
  }

  private static Candidate__c createCandidate() {
    Candidate__c c = new Candidate__c(
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Email__c = 'test@example.com'
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
      Candidate__c = candidateId
    );
    insert app;
    return app;
  }

  private static Interview__c buildInterview(
    Id stageId,
    Id appId,
    Decimal score,
    Datetime scheduledDt
  ) {
    return new Interview__c(
      Interview_Stage__c = stageId,
      Job_Application__c = appId,
      Score__c = score,
      Scheduled_DateTime__c = scheduledDt
    );
  }

  // ─── Score Validation Tests ───────────────────────────────────────────────

  @IsTest
  static void scoreBelowMaxPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    Test.startTest();
    Interview__c interview = buildInterview(stage.Id, app.Id, 80, null);
    insert interview;
    Test.stopTest();

    System.assertNotEquals(
      null,
      interview.Id,
      'Interview should be inserted when score <= max'
    );
  }

  @IsTest
  static void scoreEqualMaxPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    Test.startTest();
    Interview__c interview = buildInterview(stage.Id, app.Id, 100, null);
    insert interview;
    Test.stopTest();

    System.assertNotEquals(
      null,
      interview.Id,
      'Interview should be inserted when score = max'
    );
  }

  @IsTest
  static void scoreAboveMaxFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    Test.startTest();
    try {
      Interview__c interview = buildInterview(stage.Id, app.Id, 101, null);
      insert interview;
      System.assert(false, 'Expected exception for score exceeding max');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('cannot exceed'),
        'Error should mention score exceeds max: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  // ─── Duplicate DateTime Validation Tests ─────────────────────────────────

  @IsTest
  static void duplicateDateTimeSameCandidateFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);
    Datetime dt = Datetime.now().addDays(1);

    Interview__c first = buildInterview(stage.Id, app.Id, null, dt);
    insert first;

    Test.startTest();
    try {
      Interview__c duplicate = buildInterview(stage.Id, app.Id, null, dt);
      insert duplicate;
      System.assert(false, 'Expected exception for duplicate DateTime');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already has an interview'),
        'Error should mention duplicate DateTime: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void duplicateDateTimeDifferentTimePasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    Interview__c first = buildInterview(
      stage.Id,
      app.Id,
      null,
      Datetime.now().addDays(1)
    );
    insert first;

    Test.startTest();
    Interview__c second = buildInterview(
      stage.Id,
      app.Id,
      null,
      Datetime.now().addDays(2)
    );
    insert second;
    Test.stopTest();

    System.assertNotEquals(
      null,
      second.Id,
      'Interview should be inserted at a different DateTime'
    );
  }

  @IsTest
  static void duplicateDateTimeCancelledIgnoredPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);
    Datetime dt = Datetime.now().addDays(1);

    Interview__c cancelled = buildInterview(stage.Id, app.Id, null, dt);
    cancelled.Status__c = 'Cancelled';
    insert cancelled;

    Test.startTest();
    Interview__c newInterview = buildInterview(stage.Id, app.Id, null, dt);
    insert newInterview;
    Test.stopTest();

    System.assertNotEquals(
      null,
      newInterview.Id,
      'Cancelled interview should not block new one at same DateTime'
    );
  }
}
