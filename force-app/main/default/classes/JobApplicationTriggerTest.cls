/**
 * @description Test class for JobApplicationTrigger and JobApplicationTriggerHandler.
 *              Covers duplicate application blocking, legitimate reapplication
 *              after rejection, and applying to multiple different positions.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
@IsTest
private class JobApplicationTriggerTest {

    /**
     * @description Creates a test user with Minimum Access profile
     *              and assigns the given permission set
     * @param lastName Unique last name for the user
     * @param psName API name of the permission set to assign
     * @return User the created test user
     */
    private static User createUser(String lastName, String psName) {
        Profile p = [
            SELECT Id FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        User u = new User(
            FirstName            = 'Test',
            LastName             = lastName,
            Email                = lastName.toLowerCase() + '@talentforce.test',
            Username             = lastName.toLowerCase() + '@talentforce.test.sandbox',
            Alias                = lastName.substring(0, 4).toLowerCase(),
            TimeZoneSidKey       = 'Africa/Casablanca',
            LocaleSidKey         = 'fr_MA',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            ProfileId            = p.Id
        );
        insert u;

        PermissionSet ps = [
            SELECT Id FROM PermissionSet
            WHERE Name = :psName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId      = u.Id,
            PermissionSetId = ps.Id
        );

    return u;
  }

    /**
     * @description Creates two job positions as a Recruiter user.
     *              Job_Position__c is Public Read/Write so candidates can read them.
     */
    @TestSetup
    static void setupTestData() {
        User recruiter = createUser('Recruiter', 'TF_Recruiter');

        System.runAs(recruiter) {
            Job_Position__c positionA = new Job_Position__c(
                Title__c                    = 'Développeur Salesforce',
                Status__c                   = 'Open',
                Required_Education__c       = 'Bac+5',
                Required_Experience__c      = 2,
                Open_Positions__c           = 3,
                Max_Interview_Candidates__c = 10,
                Interview_Stages_Count__c   = 2,
                Application_Deadline__c     = Date.today().addDays(30),
                Finalize_Selection__c       = false
            );
            insert positionA;

            Job_Position__c positionB = new Job_Position__c(
                Title__c                    = 'Consultant CRM',
                Status__c                   = 'Open',
                Required_Education__c       = 'Bac+5',
                Required_Experience__c      = 1,
                Open_Positions__c           = 2,
                Max_Interview_Candidates__c = 5,
                Interview_Stages_Count__c   = 1,
                Application_Deadline__c     = Date.today().addDays(30),
                Finalize_Selection__c       = false
            );
            insert positionB;
        }
    }

    /**
     * @description Test that a first application is created successfully
     */
    @IsTest
    static void testFirstApplicationSucceeds() {
        User candidateUser = createUser('CandFirst', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c      = 'Test',
                LastName__c       = 'CandFirst',
                Email__c          = 'candfirst@talentforce.test',
                Phone__c          = '0600000011',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            Test.startTest();
            Job_Application__c app = new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = position.Id,
                Stage__c            = 'new',
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
    }

    /**
     * @description Test that a duplicate active application for the same position is blocked
     */
    @IsTest
    static void testDuplicateApplicationBlocked() {
        User candidateUser = createUser('CandDupe', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c      = 'Test',
                LastName__c       = 'CandDupe',
                Email__c          = 'canddupe@talentforce.test',
                Phone__c          = '0600000012',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            insert new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = position.Id,
                Stage__c            = 'new',
                Application_Type__c = 'Portal'
            );

            Test.startTest();
            Job_Application__c duplicate = new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = position.Id,
                Stage__c            = 'new',
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
    }

    /**
     * @description Test that a candidate can reapply after being rejected
     */
    @IsTest
    static void testReapplicationAfterRejectionAllowed() {
        User candidateUser = createUser('CandReapp', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c      = 'Test',
                LastName__c       = 'CandReapp',
                Email__c          = 'candreapp@talentforce.test',
                Phone__c          = '0600000013',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            insert new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = position.Id,
                Stage__c            = 'Rejected',
                Application_Type__c = 'Portal'
            );

            Test.startTest();
            Job_Application__c reapplication = new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = position.Id,
                Stage__c            = 'new',
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
    }

    /**
     * @description Test that a candidate can apply to multiple different positions
     */
    @IsTest
    static void testApplyingToMultiplePositionsAllowed() {
        User candidateUser = createUser('CandMulti', 'TF_Candidate');

        Job_Position__c positionA = [
            SELECT Id FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];
        Job_Position__c positionB = [
            SELECT Id FROM Job_Position__c
            WHERE Title__c = 'Consultant CRM'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c      = 'Test',
                LastName__c       = 'CandMulti',
                Email__c          = 'candmulti@talentforce.test',
                Phone__c          = '0600000014',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            Test.startTest();
            Job_Application__c appA = new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = positionA.Id,
                Stage__c            = 'new',
                Application_Type__c = 'Portal'
            );
            insert appA;

            Job_Application__c appB = new Job_Application__c(
                Candidate__c        = candidate.Id,
                Job_Position__c     = positionB.Id,
                Stage__c            = 'new',
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
}
