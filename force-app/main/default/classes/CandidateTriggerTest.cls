/**
 * @description Test class for CandidateTrigger and CandidateTriggerHandler.
 *              Covers duplicate email, duplicate phone, duplicate name flagging,
 *              and clean insert scenarios.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
@IsTest
private class CandidateTriggerTest {

    /**
     * @description Creates and returns a test user with Minimum Access profile
     * @return User the created test user
     */
    private static User createTestUser() {
        Profile p = [
            SELECT Id FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        User u = new User(
            FirstName            = 'Test',
            LastName             = 'CandidateUser',
            Email                = 'candidateuser@talentforce.test',
            Username             = 'candidateuser@talentforce.test.sandbox',
            Alias                = 'candu',
            TimeZoneSidKey       = 'Africa/Casablanca',
            LocaleSidKey         = 'fr_MA',
            EmailEncodingKey     = 'UTF-8',
            LanguageLocaleKey    = 'en_US',
            ProfileId            = p.Id
        );
        insert u;
        return u;
    }

    /**
     * @description Builds a Candidate__c record without inserting it
     * @param email The email address
     * @param phone The phone number
     * @param firstName The first name
     * @param lastName The last name
     * @return Candidate__c the built (not inserted) candidate record
     */
    private static Candidate__c buildCandidate(
        String email,
        String phone,
        String firstName,
        String lastName
    ) {
        return new Candidate__c(
            Email__c          = email,
            Phone__c          = phone,
            FirstName__c      = firstName,
            LastName__c       = lastName,
            Journey_Status__c = 'Active'
        );
    }

    /**
     * @description Test that a clean candidate insert succeeds with no errors
     */
    @IsTest
    static void testCleanInsertSucceeds() {
        User u = createTestUser();

        System.runAs(u) {
            Test.startTest();
            Candidate__c c = buildCandidate(
                'clean@test.com',
                '0600000001',
                'Clean',
                'Candidate'
            );
            insert c;
            Test.stopTest();

            System.assertNotEquals(
                null,
                c.Id,
                'Clean candidate should be inserted successfully'
            );
        }
    }

    /**
     * @description Test that inserting a candidate with a duplicate email is blocked
     */
    @IsTest
    static void testDuplicateEmailBlocked() {
        User u = createTestUser();

        System.runAs(u) {
            insert buildCandidate('duplicate@test.com', '0600000002', 'First', 'Person');

            Test.startTest();
            Candidate__c duplicate = buildCandidate(
                'duplicate@test.com',
                '0600000003',
                'Second',
                'Person'
            );
            Database.SaveResult result = Database.insert(duplicate, false);
            Test.stopTest();

            System.assert(
                !result.isSuccess(),
                'Duplicate email should be blocked'
            );
            System.assert(
                result.getErrors()[0].getMessage().contains('email'),
                'Error message should mention email'
            );
        }
    }

    /**
     * @description Test that inserting a candidate with a duplicate phone is blocked
     */
    @IsTest
    static void testDuplicatePhoneBlocked() {
        User u = createTestUser();

        System.runAs(u) {
            insert buildCandidate('first@test.com', '0600000004', 'First', 'Phone');

            Test.startTest();
            Candidate__c duplicate = buildCandidate(
                'second@test.com',
                '0600000004',
                'Second',
                'Phone'
            );
            Database.SaveResult result = Database.insert(duplicate, false);
            Test.stopTest();

            System.assert(
                !result.isSuccess(),
                'Duplicate phone should be blocked'
            );
            System.assert(
                result.getErrors()[0].getMessage().contains('phone'),
                'Error message should mention phone number'
            );
        }
    }

    /**
     * @description Test that inserting a candidate with duplicate full name
     *              is allowed but flagged for HR review
     */
    @IsTest
    static void testDuplicateNameFlagged() {
        User u = createTestUser();

        System.runAs(u) {
            insert buildCandidate('first@test.com', '0600000005', 'Mohammed', 'Alami');

            Test.startTest();
            Candidate__c sameName = buildCandidate(
                'second@test.com',
                '0600000006',
                'Mohammed',
                'Alami'
            );
            insert sameName;
            Test.stopTest();

            Candidate__c inserted = [
                SELECT Id, Duplicate_Flag__c, Duplicate_Review_Status__c
                FROM Candidate__c
                WHERE Id = :sameName.Id
            ];

            System.assertEquals(
                true,
                inserted.Duplicate_Flag__c,
                'Duplicate flag should be true'
            );
            System.assertEquals(
                'Pending',
                inserted.Duplicate_Review_Status__c,
                'Review status should be Pending'
            );
        }
    }

    /**
     * @description Test bulk insert of candidates with no duplicates
     */
    @IsTest
    static void testBulkInsertSucceeds() {
        User u = createTestUser();

        System.runAs(u) {
            List<Candidate__c> candidates = new List<Candidate__c>();
            for (Integer i = 0; i < 10; i++) {
                candidates.add(buildCandidate(
                    'bulk' + i + '@test.com',
                    '060000' + String.valueOf(i).leftPad(4, '0'),
                    'Bulk',
                    'Candidate' + i
                ));
            }

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(candidates, false);
            Test.stopTest();

            for (Database.SaveResult r : results) {
                System.assert(
                    r.isSuccess(),
                    'All bulk candidates should insert successfully'
                );
            }
        }
    }
}