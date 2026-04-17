@IsTest
private class InterviewTriggerTest {
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
    Candidate__c candidateRec = new Candidate__c(
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Email__c = 'test@example.com',
      Phone__c = '0644554253'
    );
    insert candidateRec;
    return candidateRec;
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

  private static Interview__c buildInterview(Id stageId, Id appId) {
    return new Interview__c(
      Interview_Stage__c = stageId,
      Job_Application__c = appId
    );
  }

  private static Interview__c buildInterviewWithScore(
    Id stageId,
    Id appId,
    Decimal score
  ) {
    Interview__c interviewRec = buildInterview(stageId, appId);
    interviewRec.Score__c = score;
    return interviewRec;
  }

  private static Interview__c buildInterviewWithSchedule(
    Id stageId,
    Id appId,
    Datetime scheduledDt
  ) {
    Interview__c interviewRec = buildInterview(stageId, appId);
    interviewRec.Scheduled_DateTime__c = scheduledDt;
    return interviewRec;
  }

  @IsTest
  static void scoreBelowMaxPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    Test.startTest();
    Interview__c interviewRec = buildInterviewWithScore(stage.Id, app.Id, 80);
    insert interviewRec;
    Test.stopTest();

    System.assertNotEquals(
      null,
      interviewRec.Id,
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
    Interview__c interviewRec = buildInterviewWithScore(stage.Id, app.Id, 100);
    insert interviewRec;
    Test.stopTest();

    System.assertNotEquals(
      null,
      interviewRec.Id,
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
      Interview__c interviewRec = buildInterviewWithScore(
        stage.Id,
        app.Id,
        101
      );
      insert interviewRec;
      System.assert(false, 'Expected exception for score exceeding max');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('cannot exceed'),
        'Error should mention score exceeds max: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void duplicateDateTimeSameCandidateFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 100);
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);
    Datetime dt = Datetime.now().addDays(1);

    Interview__c firstInterview = buildInterviewWithSchedule(
      stage.Id,
      app.Id,
      dt
    );
    insert firstInterview;

    Test.startTest();
    try {
      Interview__c duplicateInterview = buildInterviewWithSchedule(
        stage.Id,
        app.Id,
        dt
      );
      insert duplicateInterview;
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

    Interview__c firstInterview = buildInterviewWithSchedule(
      stage.Id,
      app.Id,
      Datetime.now().addDays(1)
    );
    insert firstInterview;

    Test.startTest();
    Interview__c secondInterview = buildInterviewWithSchedule(
      stage.Id,
      app.Id,
      Datetime.now().addDays(2)
    );
    insert secondInterview;
    Test.stopTest();

    System.assertNotEquals(
      null,
      secondInterview.Id,
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

    Interview__c cancelledInterview = buildInterviewWithSchedule(
      stage.Id,
      app.Id,
      dt
    );
    cancelledInterview.Status__c = 'Cancelled';
    insert cancelledInterview;

    Test.startTest();
    Interview__c newInterview = buildInterviewWithSchedule(
      stage.Id,
      app.Id,
      dt
    );
    insert newInterview;
    Test.stopTest();

    System.assertNotEquals(
      null,
      newInterview.Id,
      'Cancelled interview should not block new one at same DateTime'
    );
  }
}
