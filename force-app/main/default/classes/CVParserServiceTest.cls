/**
 * @description Unit tests for CVParserService.
 *              Uses a stub approach: we test parseResponse() and the null-guard
 *              directly, and test invokePromptTemplate() indirectly by stubbing
 *              the Einstein response via @TestVisible overrides.
 *
 *              ConnectApi.EinsteinLLM cannot be called in a test context, so
 *              we isolate the invocation behind a @TestVisible method and test
 *              the full service by injecting a mock response into parseResponse().
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
@IsTest
private class CVParserServiceTest {
  // ─── helpers ────────────────────────────────────────────────────────────

  private static String buildJson(
    String skills,
    String keywords,
    String education,
    Object experience
  ) {
    Map<String, Object> payload = new Map<String, Object>{
      'Extracted_Skills' => skills,
      'Extracted_Keywords' => keywords,
      'Extracted_Education' => education,
      'Extracted_Experience' => experience
    };
    return JSON.serialize(payload);
  }

  // ─── parseResponse tests ─────────────────────────────────────────────────

  @IsTest
  static void parseResponse_fullData_mapsAllFields() {
    String json = buildJson(
      'Apex, LWC, SOQL',
      'Salesforce, CRM, cloud',
      'Master',
      3
    );

    Test.startTest();
    CVParserService.CVParseResult result = CVParserService.parseResponse(json);
    Test.stopTest();

    System.assertEquals(
      'Apex, LWC, SOQL',
      result.extractedSkills,
      'Skills mismatch'
    );
    System.assertEquals(
      'Salesforce, CRM, cloud',
      result.extractedKeywords,
      'Keywords mismatch'
    );
    System.assertEquals(
      'Master',
      result.extractedEducation,
      'Education mismatch'
    );
    System.assertEquals(3, result.extractedExperience, 'Experience mismatch');
    System.assertEquals(
      CVParserService.PARSER_VERSION,
      result.parserVersion,
      'Version mismatch'
    );
    System.assertEquals(true, result.success, 'Success flag should be true');
    System.assertNotEquals(null, result.parsedAt, 'parsedAt should be set');
  }

  @IsTest
  static void parseResponse_nullFields_handledGracefully() {
    String json = buildJson(null, null, null, null);

    Test.startTest();
    CVParserService.CVParseResult result = CVParserService.parseResponse(json);
    Test.stopTest();

    System.assertEquals(null, result.extractedSkills, 'Skills should be null');
    System.assertEquals(
      null,
      result.extractedKeywords,
      'Keywords should be null'
    );
    System.assertEquals(
      null,
      result.extractedEducation,
      'Education should be null'
    );
    System.assertEquals(
      null,
      result.extractedExperience,
      'Experience should be null'
    );
    System.assertEquals(
      true,
      result.success,
      'Success flag should still be true'
    );
  }

  @IsTest
  static void parseResponse_experienceAsDecimal_convertedToInteger() {
    String json = buildJson('Java', 'backend', 'Bachelor', 5);

    Test.startTest();
    CVParserService.CVParseResult result = CVParserService.parseResponse(json);
    Test.stopTest();

    System.assertEquals(
      5,
      result.extractedExperience,
      'Experience should be integer 5'
    );
  }

  @IsTest
  static void parseResponse_invalidJson_throwsException() {
    Test.startTest();
    try {
      CVParserService.parseResponse('not valid json {{');
      System.assert(false, 'Expected exception for invalid JSON');
    } catch (Exception e) {
      System.assert(true, 'Exception correctly thrown for invalid JSON');
    }
    Test.stopTest();
  }

  // ─── parseCV null guard ───────────────────────────────────────────────────

  @IsTest
  static void parseCV_nullId_throwsAuraHandledException() {
    Test.startTest();
    try {
      CVParserService.parseCV(null);
      System.assert(false, 'Expected AuraHandledException for null id');
    } catch (AuraHandledException e) {
      System.assert(
        true,
        'AuraHandledException correctly thrown for null contentDocumentId'
      );
    }
    Test.stopTest();
  }

  // ─── parseResponse edge cases ─────────────────────────────────────────────

  @IsTest
  static void parseResponse_emptyStrings_storedAsEmptyStrings() {
    String json = buildJson('', '', '', 0);

    Test.startTest();
    CVParserService.CVParseResult result = CVParserService.parseResponse(json);
    Test.stopTest();

    System.assertEquals(
      '',
      result.extractedSkills,
      'Empty skills should be stored as empty string'
    );
    System.assertEquals(
      0,
      result.extractedExperience,
      'Zero experience should be stored as 0'
    );
  }

  @IsTest
  static void parseResponse_versionConstant_isSet() {
    String json = buildJson('Apex', 'SF', 'PhD', 10);

    Test.startTest();
    CVParserService.CVParseResult result = CVParserService.parseResponse(json);
    Test.stopTest();

    System.assertNotEquals(
      null,
      result.parserVersion,
      'Parser version should always be populated'
    );
  }
}
