/**
 * @description Unit tests for JobApplicationTriggerHandler.
 *              Covers before insert duplicate check (TF-013) and before update
 *              HITL filter review stamping and validation (TF-014).
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
@IsTest
private class JobApplicationTriggerHandlerTest {
  // ─── test data helpers ───────────────────────────────────────────────────

  /**
   * @description Creates and inserts a minimal Job_Position__c.
   * @return Inserted Job_Position__c
   */
  private static Job_Position__c createPosition() {
    Job_Position__c pos = new Job_Position__c(
      Title__c = 'Engineer',
      Required_Experience__c = 2,
      Required_Education__c = 'Bac+3'
    );
    insert pos;
    return pos;
  }

  /**
   * @description Creates and inserts a minimal Candidate__c.
   * @return Inserted Candidate__c
   */
  private static Candidate__c createCandidate() {
    Candidate__c cand = new Candidate__c(
      FirstName__c = 'Jane',
      LastName__c = 'Doe',
      Email__c = 'jane.doe@example.com',
      Phone__c = '0600000001'
    );
    insert cand;
    return cand;
  }

  /**
   * @description Creates and inserts a Job_Application__c.
   * @param candidateId Id of the Candidate__c
   * @param positionId  Id of the Job_Position__c
   * @param stage       Value for Stage__c
   * @return Inserted Job_Application__c
   */
  private static Job_Application__c createApplication(
    Id candidateId,
    Id positionId,
    String stage
  ) {
    Job_Application__c app = new Job_Application__c(
      Candidate__c = candidateId,
      Job_Position__c = positionId,
      Stage__c = stage
    );
    insert app;
    return app;
  }

  // ─── before insert: duplicate check ──────────────────────────────────────

  /**
   * @description A second active application for the same candidate and
   *              position must be blocked with an appropriate error.
   */
  @IsTest
  static void duplicateApplicationIsBlocked() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    createApplication(cand.Id, pos.Id, 'New');

    Job_Application__c dupe = new Job_Application__c(
      Candidate__c = cand.Id,
      Job_Position__c = pos.Id,
      Stage__c = 'New'
    );

    Test.startTest();
    Database.SaveResult result = Database.insert(dupe, false);
    Test.stopTest();

    System.assert(
      !result.isSuccess(),
      'Duplicate application should be blocked.'
    );
    System.assert(
      result.getErrors()[0].getMessage().contains('active application'),
      'Error message should mention active application.'
    );
  }

  /**
   * @description A candidate whose previous application is Rejected may reapply.
   */
  @IsTest
  static void reapplyAfterRejectionIsAllowed() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    createApplication(cand.Id, pos.Id, 'Rejected');

    Job_Application__c reapply = new Job_Application__c(
      Candidate__c = cand.Id,
      Job_Position__c = pos.Id,
      Stage__c = 'New'
    );

    Test.startTest();
    Database.SaveResult result = Database.insert(reapply, false);
    Test.stopTest();

    System.assert(
      result.isSuccess(),
      'Reapplication after rejection should succeed.'
    );
  }

  /**
   * @description A candidate whose previous application is Withdrawn may reapply.
   */
  @IsTest
  static void reapplyAfterWithdrawalIsAllowed() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    createApplication(cand.Id, pos.Id, 'Withdrawn');

    Job_Application__c reapply = new Job_Application__c(
      Candidate__c = cand.Id,
      Job_Position__c = pos.Id,
      Stage__c = 'New'
    );

    Test.startTest();
    Database.SaveResult result = Database.insert(reapply, false);
    Test.stopTest();

    System.assert(
      result.isSuccess(),
      'Reapplication after withdrawal should succeed.'
    );
  }

  // ─── before update: HITL filter review ───────────────────────────────────

  /**
   * @description Approving an application stamps Filter_Reviewed_By__c
   *              and Filter_Reviewed_At__c.
   */
  @IsTest
  static void approvingApplicationStampsReviewer() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(cand.Id, pos.Id, 'New');

    Test.startTest();
    app.Filter_Review_Status__c = 'Approved';
    update app;
    Test.stopTest();

    Job_Application__c result = [
      SELECT Filter_Reviewed_By__c, Filter_Reviewed_At__c
      FROM Job_Application__c
      WHERE Id = :app.Id
    ];
    System.assertNotEquals(
      null,
      result.Filter_Reviewed_By__c,
      'Reviewer should be stamped on approval.'
    );
    System.assertNotEquals(
      null,
      result.Filter_Reviewed_At__c,
      'Timestamp should be stamped on approval.'
    );
  }

  /**
   * @description Rejecting an application with a reason stamps reviewer
   *              and timestamp.
   */
  @IsTest
  static void rejectingWithReasonStampsReviewer() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(cand.Id, pos.Id, 'New');

    Test.startTest();
    app.Filter_Review_Status__c = 'Rejected';
    app.Filter_Rejection_Reason__c = 'Does not meet minimum experience.';
    update app;
    Test.stopTest();

    Job_Application__c result = [
      SELECT Filter_Reviewed_By__c, Filter_Reviewed_At__c
      FROM Job_Application__c
      WHERE Id = :app.Id
    ];
    System.assertNotEquals(
      null,
      result.Filter_Reviewed_By__c,
      'Reviewer should be stamped on rejection.'
    );
    System.assertNotEquals(
      null,
      result.Filter_Reviewed_At__c,
      'Timestamp should be stamped on rejection.'
    );
  }

  /**
   * @description Rejecting an application without a reason must be blocked.
   */
  @IsTest
  static void rejectingWithoutReasonIsBlocked() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(cand.Id, pos.Id, 'New');

    app.Filter_Review_Status__c = 'Rejected';
    app.Filter_Rejection_Reason__c = null;

    Test.startTest();
    Database.SaveResult result = Database.update(app, false);
    Test.stopTest();

    System.assert(
      !result.isSuccess(),
      'Rejection without reason should be blocked.'
    );
    System.assert(
      result.getErrors()[0].getMessage().contains('rejection reason'),
      'Error message should mention rejection reason.'
    );
  }

  /**
   * @description HR can reverse a decision by setting status back to Pending.
   */
  @IsTest
  static void reversalToPendingIsAllowed() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(cand.Id, pos.Id, 'New');

    app.Filter_Review_Status__c = 'Rejected';
    app.Filter_Rejection_Reason__c = 'Does not qualify.';
    update app;

    Test.startTest();
    app.Filter_Review_Status__c = 'Pending';
    Database.SaveResult result = Database.update(app, false);
    Test.stopTest();

    System.assert(result.isSuccess(), 'Reversal to Pending should be allowed.');
  }

  /**
   * @description Updating an unrelated field does not trigger reviewer stamping.
   */
  @IsTest
  static void unrelatedUpdateDoesNotStampReviewer() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(cand.Id, pos.Id, 'New');

    Test.startTest();
    app.Stage__c = 'Interview';
    update app;
    Test.stopTest();

    Job_Application__c result = [
      SELECT Filter_Reviewed_By__c, Filter_Reviewed_At__c
      FROM Job_Application__c
      WHERE Id = :app.Id
    ];
    System.assertEquals(
      null,
      result.Filter_Reviewed_By__c,
      'Reviewer should not be stamped on unrelated update.'
    );
    System.assertEquals(
      null,
      result.Filter_Reviewed_At__c,
      'Timestamp should not be stamped on unrelated update.'
    );
  }
}
