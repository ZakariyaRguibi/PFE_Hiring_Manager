/**
 * @description Test class for JobApplicationTrigger and JobApplicationTriggerHandler.
 *              Covers first application success, duplicate application blocking,
 *              reapplication blocking after rejection, and applying to multiple
 *              different positions.
 * @author Hiba Balhirch
 * @date 2026-04-16
 */
@IsTest
private class JobApplicationTriggerTest {

    /**
     * @description Creates a test user with Minimum Access profile
     *              and assigns the given permission set.
     * @param lastName Unique last name for the user
     * @param psName API name of the permission set to assign
     * @return User created test user
     */
    private static User createUser(String lastName, String psName) {
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

        PermissionSet ps = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :psName
            LIMIT 1
        ];

        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
        );

        return u;
    }

    /**
     * @description Creates two job positions as a Recruiter user.
     */
    @TestSetup
    static void setupTestData() {
        User recruiter = createUser('Recruiter', 'TF_Recruiter');

        System.runAs(recruiter) {
            Job_Position__c positionA = new Job_Position__c(
                Title__c = 'Développeur Salesforce',
                Status__c = 'Open',
                Required_Education__c = 'Bac+5',
                Required_Experience__c = 2,
                Open_Positions__c = 3,
                Max_Interview_Candidates__c = 10,
                Interview_Stages_Count__c = 2,
                Application_Deadline__c = Date.today().addDays(30),
                Finalize_Selection__c = false
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
                Application_Deadline__c = Date.today().addDays(30),
                Finalize_Selection__c = false
            );
            insert positionB;
        }
    }

    /**
     * @description Test that a first application is created successfully.
     */
    @IsTest
    static void testFirstApplicationSucceeds() {
        User candidateUser = createUser('CandFirst', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c = 'Test',
                LastName__c = 'CandFirst',
                Email__c = 'candfirst@talentforce.test',
                Phone__c = '0600000011',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            Test.startTest();
            Job_Application__c app = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );
            insert app;
            Test.stopTest();

            System.assertNotEquals(
                null,
                app.Id,
                'First application should be created successfully.'
            );
        }
    }

    /**
     * @description Test that a duplicate application for the same position is blocked.
     */
    @IsTest
    static void testDuplicateApplicationBlocked() {
        User candidateUser = createUser('CandDupe', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c = 'Test',
                LastName__c = 'CandDupe',
                Email__c = 'canddupe@talentforce.test',
                Phone__c = '0600000012',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            insert new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );

            Test.startTest();
            Job_Application__c duplicate = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );
            Database.SaveResult result = Database.insert(duplicate, false);
            Test.stopTest();

            System.assert(
                !result.isSuccess(),
                'Duplicate application should be blocked.'
            );
            System.assert(
                result.getErrors()[0].getMessage().contains('only once'),
                'Error message should state that the candidate can apply only once.'
            );
        }
    }

    /**
     * @description Test that reapplication after rejection is blocked.
     */
    @IsTest
    static void testReapplicationAfterRejectionIsBlocked() {
        User candidateUser = createUser('CandReapp', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c = 'Test',
                LastName__c = 'CandReapp',
                Email__c = 'candreapp@talentforce.test',
                Phone__c = '0600000013',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            insert new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'Rejected',
                Application_Type__c = 'Portal'
            );

            Test.startTest();
            Job_Application__c reapplication = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );
            Database.SaveResult result = Database.insert(reapplication, false);
            Test.stopTest();

            System.assert(
                !result.isSuccess(),
                'Reapplication after rejection should be blocked.'
            );
            System.assert(
                result.getErrors()[0].getMessage().contains('only once'),
                'Error message should state that the candidate can apply only once.'
            );
        }
    }

    /**
     * @description Test that a candidate can apply to multiple different positions.
     */
    @IsTest
    static void testApplyingToMultiplePositionsAllowed() {
        User candidateUser = createUser('CandMulti', 'TF_Candidate');

        Job_Position__c positionA = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        Job_Position__c positionB = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Consultant CRM'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c = 'Test',
                LastName__c = 'CandMulti',
                Email__c = 'candmulti@talentforce.test',
                Phone__c = '0600000014',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            Test.startTest();
            Job_Application__c appA = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = positionA.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );
            insert appA;

            Job_Application__c appB = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = positionB.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );
            insert appB;
            Test.stopTest();

            System.assertNotEquals(
                null,
                appA.Id,
                'Application to position A should succeed.'
            );
            System.assertNotEquals(
                null,
                appB.Id,
                'Application to position B should succeed.'
            );
        }
    }

    /**
     * @description Test that duplicate applications in the same insert batch are blocked.
     */
    @IsTest
    static void testDuplicateApplicationsInSameBatchBlocked() {
        User candidateUser = createUser('CandBatch', 'TF_Candidate');

        Job_Position__c position = [
            SELECT Id
            FROM Job_Position__c
            WHERE Title__c = 'Développeur Salesforce'
            LIMIT 1
        ];

        System.runAs(candidateUser) {
            Candidate__c candidate = new Candidate__c(
                FirstName__c = 'Test',
                LastName__c = 'CandBatch',
                Email__c = 'candbatch@talentforce.test',
                Phone__c = '0600000015',
                Journey_Status__c = 'Active'
            );
            insert candidate;

            Job_Application__c app1 = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );

            Job_Application__c app2 = new Job_Application__c(
                Candidate__c = candidate.Id,
                Job_Position__c = position.Id,
                Stage__c = 'New',
                Application_Type__c = 'Portal'
            );

            Test.startTest();
            Database.SaveResult[] results = Database.insert(
                new List<Job_Application__c>{ app1, app2 },
                false
            );
            Test.stopTest();

            Integer failedCount = 0;
            for (Database.SaveResult sr : results) {
                if (!sr.isSuccess()) {
                    failedCount++;
                }
            }

            System.assertEquals(
                1,
                failedCount,
                'Exactly one duplicate application in the same batch should fail.'
            );
        }
    }
}