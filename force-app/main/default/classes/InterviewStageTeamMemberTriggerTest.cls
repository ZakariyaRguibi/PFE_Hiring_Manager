@IsTest
private class InterviewStageTeamMemberTriggerTest {
  // ─── Test Data Setup ───────────────────────────────────────────────────

  private static Interview_Stage__c createStage(Id positionId, Integer num) {
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = positionId,
      Stage_Number__c = num,
      Max_Score__c = 100,
      Passing_Threshold__c = 50
    );
    insert stage;
    return stage;
  }

  private static Job_Position__c createPosition() {
    Job_Position__c pos = new Job_Position__c(Title__c = 'Test Position');
    insert pos;
    return pos;
  }

  private static User createUser() {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      Alias = 'tmtest',
      Email = 'tmtest@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'TMTest',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'tmtest_' + System.now().getTime() + '@example.com'
    );
    insert u;
    return u;
  }

  // ─── Insert Tests ──────────────────────────────────────────────────────

  @IsTest
  static void insertUniqueInterviewerPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);
    User interviewer = createUser();

    Test.startTest();
    Interview_Stage_Team_Member__c member = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer.Id
    );
    insert member;
    Test.stopTest();

    System.assertNotEquals(
      null,
      member.Id,
      'Team member should be inserted when interviewer is unique for stage'
    );
  }

  @IsTest
  static void insertDuplicateInterviewerSameStageFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);
    User interviewer = createUser();

    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer.Id
    );

    Test.startTest();
    try {
      insert new Interview_Stage_Team_Member__c(
        Interview_Stage__c = stage.Id,
        Interviewer__c = interviewer.Id
      );
      System.assert(
        false,
        'Expected DmlException for duplicate interviewer in same stage'
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already a member'),
        'Error should mention duplicate: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void insertSameInterviewerDifferentStagesPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage1 = createStage(pos.Id, 1);
    Interview_Stage__c stage2 = createStage(pos.Id, 2);
    User interviewer = createUser();

    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage1.Id,
      Interviewer__c = interviewer.Id
    );

    Test.startTest();
    Interview_Stage_Team_Member__c member2 = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage2.Id,
      Interviewer__c = interviewer.Id
    );
    insert member2;
    Test.stopTest();

    System.assertNotEquals(
      null,
      member2.Id,
      'Same interviewer should be allowed on a different stage'
    );
  }

  @IsTest
  static void insertNullInterviewerPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);

    Test.startTest();
    Interview_Stage_Team_Member__c member = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id
    );
    insert member;
    Test.stopTest();

    System.assertNotEquals(
      null,
      member.Id,
      'Team member with no interviewer (pool placeholder) should be allowed'
    );
  }

  @IsTest
  static void insertDuplicateInterviewerWithinBatchFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);
    User interviewer = createUser();

    Test.startTest();
    try {
      insert new List<Interview_Stage_Team_Member__c>{
        new Interview_Stage_Team_Member__c(
          Interview_Stage__c = stage.Id,
          Interviewer__c = interviewer.Id
        ),
        new Interview_Stage_Team_Member__c(
          Interview_Stage__c = stage.Id,
          Interviewer__c = interviewer.Id
        )
      };
      System.assert(
        false,
        'Expected DmlException for duplicate interviewer in same batch'
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already a member'),
        'Error should mention duplicate: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  // ─── Update Tests ──────────────────────────────────────────────────────

  @IsTest
  static void updateChangeToExistingInterviewerFails() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);
    User interviewer1 = createUser();
    User interviewer2 = createUser();

    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer1.Id
    );
    Interview_Stage_Team_Member__c member2 = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer2.Id
    );
    insert member2;

    Test.startTest();
    try {
      member2.Interviewer__c = interviewer1.Id;
      update member2;
      System.assert(
        false,
        'Expected DmlException when updating to a duplicate interviewer'
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already a member'),
        'Error should mention duplicate: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void updateSameInterviewerPasses() {
    Job_Position__c pos = createPosition();
    Interview_Stage__c stage = createStage(pos.Id, 1);
    User interviewer = createUser();

    Interview_Stage_Team_Member__c member = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer.Id
    );
    insert member;

    Test.startTest();
    // Update a field that doesn't affect uniqueness — if there were other fields.
    // Since there are none currently, just re-save the same record to verify no false positive.
    update member;
    Test.stopTest();

    System.assertNotEquals(
      null,
      member.Id,
      'Updating a member without changing interviewer/stage should pass'
    );
  }
}
