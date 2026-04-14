/**
 * @description Test class for CandidateTrigger.
 *              Covers duplicate email, duplicate phone, duplicate name flagging,
 *              and clean insert scenarios.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
@isTest
private class CandidateTriggerTest {

    /**
     * @description Helper method to create a base candidate record
     * @param email The email address for the candidate
     * @param phone The phone number for the candidate
     * @param firstName The first name
     * @param lastName The last name
     * @return Candidate__c the inserted candidate record
     */
    private static Candidate__c createCandidate(
        String email, String phone, String firstName, String lastName
    ) {
        Candidate__c c = new Candidate__c(
            Email__c = email,
            Phone__c = phone,
            FirstName__c = firstName,
            LastName__c = lastName,
            Journey_Status__c = 'Active'
        );
        insert c;
        return c;
    }

    /**
     * @description Test that a clean candidate insert succeeds with no errors
     */
    @isTest
    static void testCleanInsertSucceeds() {
        Test.startTest();
        Candidate__c c = createCandidate(
            'clean@test.com', '0600000001', 'Clean', 'Candidate'
        );
        Test.stopTest();

        System.assertNotEquals(null, c.Id, 'Clean candidate should be inserted successfully');
    }

    /**
     * @description Test that inserting a candidate with a duplicate email is blocked
     */
    @isTest
    static void testDuplicateEmailBlocked() {
        createCandidate('duplicate@test.com', '0600000002', 'First', 'Person');

        Test.startTest();
        Candidate__c duplicate = new Candidate__c(
            Email__c = 'duplicate@test.com',
            Phone__c = '0600000003',
            FirstName__c = 'Second',
            LastName__c = 'Person',
            Journey_Status__c = 'Active'
        );

        Database.SaveResult result = Database.insert(duplicate, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Duplicate email should be blocked');
        System.assert(
            result.getErrors()[0].getMessage().contains('email'),
            'Error message should mention email'
        );
    }

    /**
     * @description Test that inserting a candidate with a duplicate phone is blocked
     */
    @isTest
    static void testDuplicatePhoneBlocked() {
        createCandidate('first@test.com', '0600000004', 'First', 'Phone');

        Test.startTest();
        Candidate__c duplicate = new Candidate__c(
            Email__c = 'second@test.com',
            Phone__c = '0600000004',
            FirstName__c = 'Second',
            LastName__c = 'Phone',
            Journey_Status__c = 'Active'
        );

        Database.SaveResult result = Database.insert(duplicate, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Duplicate phone should be blocked');
        System.assert(
            result.getErrors()[0].getMessage().contains('phone'),
            'Error message should mention phone number'
        );
    }

    /**
     * @description Test that inserting a candidate with duplicate full name
     *              is allowed but flagged for HR review
     */
    @isTest
    static void testDuplicateNameFlagged() {
        createCandidate('first@test.com', '0600000005', 'Mohammed', 'Alami');

        Test.startTest();
        Candidate__c sameName = new Candidate__c(
            Email__c = 'second@test.com',
            Phone__c = '0600000006',
            FirstName__c = 'Mohammed',
            LastName__c = 'Alami',
            Journey_Status__c = 'Active'
        );
        insert sameName;
        Test.stopTest();

        Candidate__c inserted = [
            SELECT Id, Duplicate_Flag__c, Duplicate_Review_Status__c
            FROM Candidate__c
            WHERE Id = :sameName.Id
        ];

        System.assertEquals(true, inserted.Duplicate_Flag__c, 'Duplicate flag should be true');
        System.assertEquals('Pending', inserted.Duplicate_Review_Status__c, 'Review status should be Pending');
    }
}