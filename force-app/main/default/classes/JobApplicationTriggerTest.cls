/**
 * @description Test class for JobApplicationTrigger.
 *              Covers duplicate application blocking, legitimate reapplication
 *              after rejection, and applying to multiple different positions.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
@isTest
private class JobApplicationTriggerTest {
  /**
   * @description Creates test data: one candidate and two job positions
   */
  @TestSetup
  static void setupTestData() {
    Candidate__c candidate = new Candidate__c(
      Email__c = 'test@talentforce.com',
      Phone__c = '0600000099',
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Journey_Status__c = 'Active'
    );
    insert candidate;

    Job_Position__c positionA = new Job_Position__c(
      Title__c = 'Développeur Salesforce',
      Status__c = 'Open',
      Required_Education__c = 'Bac+5',
      Required_Experience__c = 2,
      Open_Positions__c = 3,
      Max_Interview_Candidates__c = 10,
      Interview_Stages_Count__c = 2,
      Application_Deadline__c = Date.today().addDays(30)
    );
    insert positionA;

    Job_Position__c positionB = new Job_Position__c(
      Title__c = 'Consultant CRM',
      Status__c = 'Open',
      Required_Education__c = 'Bac+5',
      Required_Experience__c = 1,
      Open_Positions__c = 2,
      Max_Interview_Candidates__c = 5,
      Interview_Stages_Count__c = 1,
      Application_Deadline__c = Date.today().addDays(30)
    );
    insert positionB;
  }

  /**
   * @description Test that a first application is created successfully
   */
  @isTest
  static void testFirstApplicationSucceeds() {
    Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
    Job_Position__c position = [
      SELECT Id
      FROM Job_Position__c
      WHERE Title__c = 'Développeur Salesforce'
    ];

    Test.startTest();
    Job_Application__c app = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );
    insert app;
    Test.stopTest();

    System.assertNotEquals(
      null,
      app.Id,
      'First application should be created successfully'
    );
  }

  /**
   * @description Test that a duplicate active application for the same position is blocked
   */
  @isTest
  static void testDuplicateApplicationBlocked() {
    Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
    Job_Position__c position = [
      SELECT Id
      FROM Job_Position__c
      WHERE Title__c = 'Développeur Salesforce'
    ];

    insert new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );

    Test.startTest();
    Job_Application__c duplicate = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );

    Database.SaveResult result = Database.insert(duplicate, false);
    Test.stopTest();

    System.assert(
      !result.isSuccess(),
      'Duplicate application should be blocked'
    );
    System.assert(
      result.getErrors()[0].getMessage().contains('active application'),
      'Error message should mention active application'
    );
  }

  /**
   * @description Test that a candidate can reapply after being rejected
   */
  @isTest
  static void testReapplicationAfterRejectionAllowed() {
    Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
    Job_Position__c position = [
      SELECT Id
      FROM Job_Position__c
      WHERE Title__c = 'Développeur Salesforce'
    ];

    Job_Application__c first = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Stage__c = 'Rejected',
      Application_Type__c = 'Portal'
    );
    insert first;

    Test.startTest();
    Job_Application__c reapplication = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = position.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );
    insert reapplication;
    Test.stopTest();

    System.assertNotEquals(
      null,
      reapplication.Id,
      'Reapplication after rejection should be allowed'
    );
  }

  /**
   * @description Test that a candidate can apply to multiple different positions
   */
  @isTest
  static void testApplyingToMultiplePositionsAllowed() {
    Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
    Job_Position__c positionA = [
      SELECT Id
      FROM Job_Position__c
      WHERE Title__c = 'Développeur Salesforce'
    ];
    Job_Position__c positionB = [
      SELECT Id
      FROM Job_Position__c
      WHERE Title__c = 'Consultant CRM'
    ];

    Test.startTest();
    Job_Application__c appA = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = positionA.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );
    insert appA;

    Job_Application__c appB = new Job_Application__c(
      Candidate__c = candidate.Id,
      Job_Position__c = positionB.Id,
      Stage__c = 'new',
      Application_Type__c = 'Portal'
    );
    insert appB;
    Test.stopTest();

    System.assertNotEquals(
      null,
      appA.Id,
      'Application to position A should succeed'
    );
    System.assertNotEquals(
      null,
      appB.Id,
      'Application to position B should succeed'
    );
  }
}
