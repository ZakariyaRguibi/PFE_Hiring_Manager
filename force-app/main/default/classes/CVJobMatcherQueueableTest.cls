/**
 * @description Unit tests for CVJobMatcherQueueable.
 *              ConnectApi.EinsteinLLM cannot be called in a test context, so
 *              the Einstein invocation is isolated in invokePromptTemplate().
 *              All business logic lives in buildUpdate() and toDecimal(),
 *              which are tested directly via @TestVisible.
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
@IsTest
private class CVJobMatcherQueueableTest {
  // inner input class

  /**
   * @description Carries all fields needed to build a CV_Job_Matcher JSON response.
   *              Using an inner class avoids an ExcessiveParameterList violation.
   */
  private class MatcherInput {
    /** @description Skills match score (0-100). */
    Object skillsScore;
    /** @description Education score (0-100). */
    Object educationScore;
    /** @description Experience score (0-100). */
    Object experienceScore;
    /** @description Keywords score (0-100). */
    Object keywordsScore;
    /** @description Weighted final score (0-100). */
    Object finalScore;
    /** @description Whether the candidate passed the hard filter. */
    Boolean passedHardFilter;
    /** @description AI filter decision: Approved or Rejected. */
    String decision;
    /** @description Reason for rejection, null if approved. */
    String rejectionReason;
  }

  // ─── test data helpers ───────────────────────────────────────────────────

  /**
   * @description Creates a minimal Job_Position__c for test use.
   * @return Inserted Job_Position__c
   */
  private static Job_Position__c createPosition() {
    Job_Position__c pos = new Job_Position__c(
      Title__c = 'Test Position',
      Required_Experience__c = 3,
      Required_Education__c = 'Bac+5'
    );
    insert pos;
    return pos;
  }

  /**
   * @description Creates a minimal Candidate__c for test use.
   * @return Inserted Candidate__c
   */
  private static Candidate__c createCandidate() {
    Candidate__c cand = new Candidate__c(
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Email__c = 'test@talentforce.test',
      Phone__c = '0600000099'
    );
    insert cand;
    return cand;
  }

  /**
   * @description Creates a Job_Application__c with parsed CV data already set.
   * @param posId  Id of the related Job_Position__c
   * @param candId Id of the related Candidate__c
   * @return Inserted Job_Application__c
   */
  private static Job_Application__c createApplication(Id posId, Id candId) {
    Job_Application__c app = new Job_Application__c(
      Job_Position__c = posId,
      Candidate__c = candId,
      Extracted_Skills__c = 'Apex, LWC, SOQL',
      Extracted_Keywords__c = 'Salesforce, CRM',
      Extracted_Education__c = 'Master',
      Extracted_Experience__c = 3
    );
    insert app;
    return app;
  }

  /**
   * @description Serializes a MatcherInput into the JSON shape returned by CV_Job_Matcher.
   * @param input All scoring fields
   * @return JSON string
   */
  private static String buildJson(MatcherInput input) {
    Map<String, Object> payload = new Map<String, Object>{
      'Skills_Match_Score' => input.skillsScore,
      'Education_Score' => input.educationScore,
      'Experience_Score' => input.experienceScore,
      'Keywords_Score' => input.keywordsScore,
      'Final_Score' => input.finalScore,
      'Passed_Hard_Filter' => input.passedHardFilter,
      'AI_Filter_Decision' => input.decision,
      'Filter_Rejection_Reason' => input.rejectionReason
    };
    return JSON.serialize(payload);
  }

  // ─── buildUpdate: perfect match

  /**
   * @description Perfect match: all scores at 100, hard filter passed, approved.
   */
  @IsTest
  static void buildUpdatePerfectMatch() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = 100;
    input.educationScore = 100;
    input.experienceScore = 100;
    input.keywordsScore = 100;
    input.finalScore = 100;
    input.passedHardFilter = true;
    input.decision = 'Approved';
    input.rejectionReason = null;

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      100,
      result.Skills_Match_Score__c,
      'Skills score should be 100'
    );
    System.assertEquals(
      100,
      result.Education_Score__c,
      'Education score should be 100'
    );
    System.assertEquals(
      100,
      result.Experience_Score__c,
      'Experience score should be 100'
    );
    System.assertEquals(
      100,
      result.Keywords_Score__c,
      'Keywords score should be 100'
    );
    System.assertEquals(100, result.AI_Score__c, 'AI score should be 100');
    System.assertEquals(
      true,
      result.Passed_Hard_Filter__c,
      'Hard filter should pass'
    );
    System.assertEquals(
      'Approved',
      result.AI_Filter_Decision__c,
      'Decision should be Approved'
    );
    System.assertEquals(
      null,
      result.Filter_Rejection_Reason__c,
      'No rejection reason for approved'
    );
    System.assertNotEquals(
      null,
      result.AI_Scored_At__c,
      'AI_Scored_At should be set'
    );
  }

  // ─── buildUpdate: partial match ──────────────────────────────────────────

  /**
   * @description Partial match: mixed scores, hard filter passes.
   */
  @IsTest
  static void buildUpdatePartialMatch() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = 75;
    input.educationScore = 50;
    input.experienceScore = 75;
    input.keywordsScore = 50;
    input.finalScore = 68;
    input.passedHardFilter = true;
    input.decision = 'Approved';
    input.rejectionReason = null;

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      75,
      result.Skills_Match_Score__c,
      'Skills score should be 75'
    );
    System.assertEquals(
      50,
      result.Education_Score__c,
      'Education score should be 50'
    );
    System.assertEquals(
      75,
      result.Experience_Score__c,
      'Experience score should be 75'
    );
    System.assertEquals(
      50,
      result.Keywords_Score__c,
      'Keywords score should be 50'
    );
    System.assertEquals(68, result.AI_Score__c, 'AI score should be 68');
    System.assertEquals(
      true,
      result.Passed_Hard_Filter__c,
      'Hard filter should pass'
    );
  }

  // ─── buildUpdate: no match ───────────────────────────────────────────────

  /**
   * @description No match: all scores at 0, hard filter fails, rejected.
   */
  @IsTest
  static void buildUpdateNoMatch() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = 0;
    input.educationScore = 0;
    input.experienceScore = 0;
    input.keywordsScore = 0;
    input.finalScore = 0;
    input.passedHardFilter = false;
    input.decision = 'Rejected';
    input.rejectionReason = 'Candidate does not meet minimum requirements';

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.Skills_Match_Score__c,
      'Skills score should be 0'
    );
    System.assertEquals(0, result.AI_Score__c, 'AI score should be 0');
    System.assertEquals(
      false,
      result.Passed_Hard_Filter__c,
      'Hard filter should fail'
    );
    System.assertEquals(
      'Rejected',
      result.AI_Filter_Decision__c,
      'Decision should be Rejected'
    );
    System.assertNotEquals(
      null,
      result.Filter_Rejection_Reason__c,
      'Rejection reason should be set'
    );
  }

  // ─── buildUpdate: missing parsed data ────────────────────────────────────

  /**
   * @description Missing data: null scores from Einstein are stored as null without throwing.
   */
  @IsTest
  static void buildUpdateHandlesMissingData() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = null;
    input.educationScore = null;
    input.experienceScore = null;
    input.keywordsScore = null;
    input.finalScore = null;
    input.passedHardFilter = false;
    input.decision = null;
    input.rejectionReason = null;

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      null,
      result.Skills_Match_Score__c,
      'Null skills score should be stored as null'
    );
    System.assertEquals(
      null,
      result.AI_Score__c,
      'Null final score means null AI score'
    );
    System.assertNotEquals(
      null,
      result.AI_Scored_At__c,
      'AI_Scored_At should always be set'
    );
  }

  // ─── buildUpdate: AI score clamping ──────────────────────────────────────

  /**
   * @description AI_Score is clamped to 100 even if Einstein returns a higher value.
   */
  @IsTest
  static void buildUpdateClampsScoreAbove100() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = 100;
    input.educationScore = 100;
    input.experienceScore = 100;
    input.keywordsScore = 100;
    input.finalScore = 150;
    input.passedHardFilter = true;
    input.decision = 'Approved';
    input.rejectionReason = null;

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      100,
      result.AI_Score__c,
      'AI score should be clamped to 100'
    );
  }

  /**
   * @description AI_Score is clamped to 0 if Einstein returns a negative value.
   */
  @IsTest
  static void buildUpdateClampsScoreBelow0() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);

    MatcherInput input = new MatcherInput();
    input.skillsScore = 0;
    input.educationScore = 0;
    input.experienceScore = 0;
    input.keywordsScore = 0;
    input.finalScore = -10;
    input.passedHardFilter = false;
    input.decision = 'Rejected';
    input.rejectionReason = 'Below minimum';

    Test.startTest();
    Job_Application__c result = CVJobMatcherQueueable.buildUpdate(
      app.Id,
      buildJson(input)
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.AI_Score__c,
      'AI score should be clamped to 0'
    );
  }

  // ─── toDecimal ───────────────────────────────────────────────────────────

  /**
   * @description toDecimal returns null for null input.
   */
  @IsTest
  static void toDecimalHandlesNull() {
    Test.startTest();
    Decimal result = CVJobMatcherQueueable.toDecimal(null);
    Test.stopTest();

    System.assertEquals(null, result, 'toDecimal(null) should return null');
  }

  /**
   * @description toDecimal converts integer JSON values correctly.
   */
  @IsTest
  static void toDecimalConvertsInteger() {
    Test.startTest();
    Decimal result = CVJobMatcherQueueable.toDecimal(75);
    Test.stopTest();

    System.assertEquals(75, result, 'toDecimal should convert 75 correctly');
  }

  // ─── execute: non-existent application ───────────────────────────────────

  @IsTest
  static void executeWithUnknownIdCompletesSilently() {
    Job_Position__c pos = createPosition();
    Candidate__c cand = createCandidate();
    Job_Application__c app = createApplication(pos.Id, cand.Id);
    Id deletedId = app.Id;
    delete app;

    Test.startTest();
    System.enqueueJob(new CVJobMatcherQueueable(deletedId));
    Test.stopTest();

    System.assert(true, 'Should complete without throwing for deleted application Id');
  }
}
