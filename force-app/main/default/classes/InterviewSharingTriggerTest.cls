/**
 * @description Test class for InterviewSharingTrigger and InterviewSharingHandler.
 */
@IsTest
private class InterviewSharingTriggerTest {
  private static User createTestUser(String lastName) {
    Profile profileRec = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];

    User userRec = new User(
      FirstName = 'Test',
      LastName = lastName,
      Email = lastName.toLowerCase() + '@talentforce.test',
      Username = lastName.toLowerCase() +
        '.' +
        System.currentTimeMillis() +
        '@talentforce.test',
      Alias = lastName.substring(0, 4).toLowerCase(),
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'fr_MA',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = profileRec.Id
    );
    insert userRec;
    return userRec;
  }

  private static Map<String, SObject> createTestData() {
    User interviewer = createTestUser('Interviewer');
    User interviewer2 = createTestUser('Intervwr2');

    Job_Position__c position = new Job_Position__c(
      Title__c = 'Test Position',
      Finalize_Selection__c = false
    );
    insert position;

    Candidate__c candidate = new Candidate__c(
      FirstName__c = 'Ahmed',
      LastName__c = 'Test',
      Email__c = 'ahmed.test@talentforce.test',
      Phone__c = '0600000000',
      Duplicate_Flag__c = false
    );
    insert candidate;

    Job_Application__c application = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Passed_Hard_Filter__c = false
    );
    insert application;

    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = position.Id,
      Stage_Number__c = 1,
      Is_Active__c = false
    );
    insert stage;

    Interview_Stage__c stage2 = new Interview_Stage__c(
      Job_Position__c = position.Id,
      Stage_Number__c = 2,
      Is_Active__c = false
    );
    insert stage2;

    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage.Id,
      Interviewer__c = interviewer.Id
    );

    insert new Interview_Stage_Team_Member__c(
      Interview_Stage__c = stage2.Id,
      Interviewer__c = interviewer.Id
    );

    stage.Is_Active__c = true;
    stage2.Is_Active__c = true;
    update new List<Interview_Stage__c>{ stage, stage2 };

    return new Map<String, SObject>{
      'interviewer' => interviewer,
      'interviewer2' => interviewer2,
      'candidate' => candidate,
      'application' => application,
      'stage' => stage,
      'stage2' => stage2
    };
  }

  private static Interview__c createInterview(
    Id appId,
    Id stageId,
    Id interviewerId
  ) {
    Interview__c interviewRec = new Interview__c(
      Job_Application__c = appId,
      Interview_Stage__c = stageId,
      Interviewer__c = interviewerId,
      Auto_Reassigned__c = false,
      Passes_To_Next_Stage__c = false
    );
    insert interviewRec;
    return interviewRec;
  }

  @IsTest
  static void testShareCreatedOnInsert() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    System.runAs(interviewer) {
      Test.startTest();
      Interview__c interviewRec = createInterview(
        app.Id,
        stage.Id,
        interviewer.Id
      );
      Test.stopTest();

      List<Candidate__Share> candidateShares = [
        SELECT Id, AccessLevel
        FROM Candidate__Share
        WHERE
          ParentId = :candidate.Id
          AND UserOrGroupId = :interviewer.Id
          AND RowCause = 'Manual'
      ];
      System.assertEquals(1, candidateShares.size());
      System.assertEquals('Read', candidateShares[0].AccessLevel);

      List<Interview__Share> interviewShares = [
        SELECT Id, AccessLevel
        FROM Interview__Share
        WHERE
          ParentId = :interviewRec.Id
          AND UserOrGroupId = :interviewer.Id
          AND RowCause = 'Manual'
      ];
      System.assertEquals(1, interviewShares.size());
      System.assertEquals('Edit', interviewShares[0].AccessLevel);
    }
  }

  @IsTest
  static void testShareUpdatedOnInterviewerChange() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    User interviewer2 = (User) data.get('interviewer2');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    System.runAs(interviewer) {
      Interview__c interviewRec = createInterview(
        app.Id,
        stage.Id,
        interviewer.Id
      );

      Test.startTest();
      interviewRec.Interviewer__c = interviewer2.Id;
      update interviewRec;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Candidate__Share
          WHERE
            ParentId = :candidate.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Interview__Share
          WHERE
            ParentId = :interviewRec.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Candidate__Share
          WHERE
            ParentId = :candidate.Id
            AND UserOrGroupId = :interviewer2.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Interview__Share
          WHERE
            ParentId = :interviewRec.Id
            AND UserOrGroupId = :interviewer2.Id
            AND RowCause = 'Manual'
        ]
      );
    }
  }

  @IsTest
  static void testShareDeletedOnInterviewDelete() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');

    System.runAs(interviewer) {
      Interview__c interviewRec = createInterview(
        app.Id,
        stage.Id,
        interviewer.Id
      );
      Id interviewId = interviewRec.Id;

      Test.startTest();
      delete interviewRec;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Candidate__Share
          WHERE
            ParentId = :candidate.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Interview__Share
          WHERE
            ParentId = :interviewId
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );
    }
  }

  @IsTest
  static void testCandidateSharePreservedWhenOtherInterviewExists() {
    Map<String, SObject> data = createTestData();
    User interviewer = (User) data.get('interviewer');
    User interviewer2 = (User) data.get('interviewer2');
    Candidate__c candidate = (Candidate__c) data.get('candidate');
    Job_Application__c app = (Job_Application__c) data.get('application');
    Interview_Stage__c stage = (Interview_Stage__c) data.get('stage');
    Interview_Stage__c stage2 = (Interview_Stage__c) data.get('stage2');

    System.runAs(interviewer) {
      Interview__c interview1 = createInterview(
        app.Id,
        stage.Id,
        interviewer.Id
      );
      Interview__c interview2 = createInterview(
        app.Id,
        stage2.Id,
        interviewer.Id
      );

      Test.startTest();
      interview1.Interviewer__c = interviewer2.Id;
      update interview1;
      Test.stopTest();

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Candidate__Share
          WHERE
            ParentId = :candidate.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Interview__Share
          WHERE
            ParentId = :interview1.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Interview__Share
          WHERE
            ParentId = :interview2.Id
            AND UserOrGroupId = :interviewer.Id
            AND RowCause = 'Manual'
        ]
      );
    }
  }
}
