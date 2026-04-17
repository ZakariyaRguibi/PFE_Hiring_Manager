/**
 * @description Test class for InterviewSharingTrigger and InterviewSharingHandler.
 *              Verifies that Candidate__Share and Interview__Share records are correctly
 *              created, preserved, and deleted based on Interview assignment changes.
 *
 * @author      Hiba Balhirch
 * @version     1.0
 */
@isTest
private class InterviewSharingTriggerTest {
  // -----------------------------------------------
  // TEST DATA SETUP
  // -----------------------------------------------

  /**
   * @description Creates a test User with Minimum Access profile.
   * @param lastName Unique last name for the user
   * @return User The created test user
   */
  private static User createTestUser(String lastName) {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User u = new User(
      FirstName = 'Test',
      LastName = lastName,
      Email = lastName.toLowerCase() + '@talentforce.test',
      Username = lastName.toLowerCase() + '@talentforce.test.sandbox',
      Alias = lastName.substring(0, 4).toLowerCase(),
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'fr_MA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert u;
    return u;
  }

  /**
   * @description Creates all shared test data used across test methods.
   * @return Map<String, SObject> Map of created test records by key
   */
  private static Map<String, SObject> createTestData() {
    User interviewer = createTestUser('Interviewer');
    User interviewer2 = createTestUser('Intervwr2');

    // Job Position
    Job_Position__c position = new Job_Position__c(
      Title__c = 'Test Position',
      Finalize_Selection__c = false
    );
    insert position;

    // Candidate
    Candidate__c candidate = new Candidate__c(
      FirstName__c = 'Ahmed',
      LastName__c = 'Test',
      Email__c = 'ahmed.test@talentforce.test',
      Phone__c = '0600000000',
      Duplicate_Flag__c = false
    );
    insert candidate;

    // Job Application
    Job_Application__c application = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Passed_Hard_Filter__c = false
    );
    insert application;

    // Interview Stage 1 — created inactive first
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = position.Id,
      Stage_Number__c = 1,
      Is_Active__c = false
    );
    insert stage;

    // Interview Stage 2 — created inactive first
    Interview_Stage__c stage2 = new Interview_Stage__c(
      Job_Position__c = position.Id,
      Stage_Number__c = 2,
      Is_Active__c = false
    );
    insert stage2;

    // Team members required before activation
    Interview_Stage_Team_Member__c member1 = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer.Id
    );
    insert member1;

    Interview_Stage_Team_Member__c member2 = new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage2.Id,
      Interviewer__c = interviewer.Id
    );
    insert member2;

    // Now activate both stages
    stage.Is_Active__c = true;
    stage2.Is_Active__c = true;
    update new List<Interview_Stage__c>{ stage, stage2 };

    return new Map<String, SObject>{
      'interviewer' => interviewer,
      'interviewer2' => interviewer2,
      'position' => position,
      'candidate' => candidate,
      'application' => application,
      'stage' => stage,
      'stage2' => stage2
    };
  }

  /**
   * @description Helper to create an Interview__c record.
   * @param appId Job Application Id
   * @param stageId Interview Stage Id
   * @param interviewerId Interviewer User Id
   * @return Interview__c The created interview
   */
  private static Interview__c createInterview(
    Id appId,
    Id stageId,
    Id interviewerId
  ) {
    Interview__c inv = new Interview__c(
      Job_Application__c = appId,
      Interview_Stage__c = stageId,
      Interviewer__c = interviewerId,
      Auto_Reassigned__c = false,
      Passes_To_Next_Stage__c = false
    );
    insert inv;
    return inv;
  }

  // -----------------------------------------------
  // TEST 1: Share created on insert
  // -----------------------------------------------

  /**
   * @description Verifies that when an Interview is created with an Interviewer,
   *              both Candidate__Share and Interview__Share are created.
   */
  @isTest
  static void testShareCreatedOnInsert() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    Test.startTest();
    Interview__c interview = createInterview(app.Id, stage.Id, interviewer.Id);
    Test.stopTest();

    // Verify Candidate__Share created
    List<Candidate__Share> candidateShares = [
      SELECT Id, AccessLevel
      FROM Candidate__Share
      WHERE
        ParentId = :candidate.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      candidateShares.size(),
      'Candidate__Share should be created for the interviewer'
    );
    System.assertEquals(
      'Read',
      candidateShares[0].AccessLevel,
      'Candidate access level should be Read'
    );

    // Verify Interview__Share created
    List<Interview__Share> interviewShares = [
      SELECT Id, AccessLevel
      FROM Interview__Share
      WHERE
        ParentId = :interview.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      interviewShares.size(),
      'Interview__Share should be created for the interviewer'
    );
    System.assertEquals(
      'Edit',
      interviewShares[0].AccessLevel,
      'Interview access level should be Edit'
    );
  }

  // -----------------------------------------------
  // TEST 2: Shares updated when interviewer changes
  // -----------------------------------------------

  /**
   * @description Verifies that when the Interviewer changes,
   *              old shares are revoked and new shares are created.
   */
  @isTest
  static void testShareUpdatedOnInterviewerChange() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    User interviewer2 = (User) data.get('interviewer2');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    Interview__c interview = createInterview(app.Id, stage.Id, interviewer.Id);

    Test.startTest();
    interview.Interviewer__c = interviewer2.Id;
    update interview;
    Test.stopTest();

    // Old interviewer — no Candidate__Share
    List<Candidate__Share> oldCandidateShares = [
      SELECT Id
      FROM Candidate__Share
      WHERE
        ParentId = :candidate.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      0,
      oldCandidateShares.size(),
      'Old interviewer Candidate__Share should be deleted'
    );

    // Old interviewer — no Interview__Share
    List<Interview__Share> oldInterviewShares = [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId = :interview.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      0,
      oldInterviewShares.size(),
      'Old interviewer Interview__Share should be deleted'
    );

    // New interviewer — Candidate__Share exists
    List<Candidate__Share> newCandidateShares = [
      SELECT Id
      FROM Candidate__Share
      WHERE
        ParentId = :candidate.Id
        AND UserOrGroupId = :interviewer2.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      newCandidateShares.size(),
      'New interviewer Candidate__Share should be created'
    );

    // New interviewer — Interview__Share exists
    List<Interview__Share> newInterviewShares = [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId = :interview.Id
        AND UserOrGroupId = :interviewer2.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      newInterviewShares.size(),
      'New interviewer Interview__Share should be created'
    );
  }

  // -----------------------------------------------
  // TEST 3: Shares deleted on interview delete
  // -----------------------------------------------

  /**
   * @description Verifies that when an Interview is deleted,
   *              both Candidate__Share and Interview__Share are revoked.
   */
  @isTest
  static void testShareDeletedOnInterviewDelete() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    Interview__c interview = createInterview(app.Id, stage.Id, interviewer.Id);
    Id interviewId = interview.Id;

    Test.startTest();
    delete interview;
    Test.stopTest();

    // Candidate__Share deleted
    List<Candidate__Share> candidateShares = [
      SELECT Id
      FROM Candidate__Share
      WHERE
        ParentId = :candidate.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      0,
      candidateShares.size(),
      'Candidate__Share should be deleted when interview is deleted'
    );

    // Interview__Share deleted
    List<Interview__Share> interviewShares = [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId = :interviewId
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      0,
      interviewShares.size(),
      'Interview__Share should be deleted when interview is deleted'
    );
  }

  // -----------------------------------------------
  // TEST 4: Candidate__Share preserved when
  //         interviewer has another active interview
  // -----------------------------------------------

  /**
   * @description Verifies that Candidate__Share is preserved when the interviewer
   *              is removed from one interview but still has another active
   *              interview with the same candidate.
   *              Interview__Share for the removed interview should be deleted.
   */
  @isTest
  static void testCandidateSharePreservedWhenOtherInterviewExists() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    User interviewer2 = (User) data.get('interviewer2');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');
    Interview_Stage__c stage2 = (Interview_Stage__c) data.get('stage2');

    // Same interviewer on two stages for same candidate
    Interview__c interview1 = createInterview(app.Id, stage.Id, interviewer.Id);
    Interview__c interview2 = createInterview(
      app.Id,
      stage2.Id,
      interviewer.Id
    );

    Test.startTest();
    interview1.Interviewer__c = interviewer2.Id;
    update interview1;
    Test.stopTest();

    // Candidate__Share preserved — interviewer still on stage 2
    List<Candidate__Share> candidateShares = [
      SELECT Id
      FROM Candidate__Share
      WHERE
        ParentId = :candidate.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      candidateShares.size(),
      'Candidate__Share should be preserved — interviewer still has stage 2'
    );

    // Interview__Share for interview1 deleted
    List<Interview__Share> interview1Shares = [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId = :interview1.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      0,
      interview1Shares.size(),
      'Interview__Share for stage 1 should be deleted'
    );

    // Interview__Share for interview2 preserved
    List<Interview__Share> interview2Shares = [
      SELECT Id
      FROM Interview__Share
      WHERE
        ParentId = :interview2.Id
        AND UserOrGroupId = :interviewer.Id
        AND RowCause = 'Manual'
    ];
    System.assertEquals(
      1,
      interview2Shares.size(),
      'Interview__Share for stage 2 should be preserved'
    );
  }
}
