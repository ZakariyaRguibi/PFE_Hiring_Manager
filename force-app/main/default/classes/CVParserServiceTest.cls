/**
 * @description Unit tests for CVParserService.
 *              ConnectApi.EinsteinLLM cannot be called in a test context, so
 *              the Einstein invocation is isolated behind a @TestVisible method.
 *              All business logic lives in parseResponse(), which is tested directly.
 *
 * @author Marwane Romani
 * @date 2026-04-30
 */
@IsTest
private class CVParserServiceTest {
  /**
   * @description Builds a serialized JSON string matching the CV_Parser prompt output shape.
   * @param skills     Extracted skills value
   * @param keywords   Extracted keywords value
   * @param education  Extracted education value
   * @param experience Extracted experience value
   * @return           JSON string
   */
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

  /**
   * @description Happy path: all four fields populated, metadata stamped correctly.
   */
  @IsTest
  static void parseResponseMapsAllFields() {
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

  /**
   * @description Null fields from Einstein are stored as null without throwing.
   */
  @IsTest
  static void parseResponseHandlesNullFields() {
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

  /**
   * @description JSON numbers deserialize as Decimal in Apex — Integer.valueOf() conversion is verified.
   */
  @IsTest
  static void parseResponseConvertsExperienceToInteger() {
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

  /**
   * @description Malformed JSON from Einstein throws an exception rather than silently producing bad data.
   */
  @IsTest
  static void parseResponseThrowsOnInvalidJson() {
    Test.startTest();
    try {
      CVParserService.parseResponse('not valid json {{');
      System.assert(false, 'Expected exception for invalid JSON');
    } catch (Exception e) {
      System.assert(true, 'Exception correctly thrown for invalid JSON');
    }
    Test.stopTest();
  }

  /**
   * @description Null contentDocumentId throws AuraHandledException before calling Einstein.
   */
  @IsTest
  static void parseCVThrowsOnNullId() {
    Test.startTest();
    try {
      CVParserService.parseCV(null);
      System.assert(false, 'Expected AuraHandledException for null id');
    } catch (AuraHandledException e) {
      // AuraHandledException.getMessage() returns 'Script-thrown exception' at runtime,
      // not the actual message — asserting the correct exception type is sufficient.
      System.assert(
        true,
        'AuraHandledException correctly thrown for null contentDocumentId'
      );
    }
    Test.stopTest();
  }

  /**
   * @description Empty strings and zero experience are stored as-is, not converted to null.
   */
  @IsTest
  static void parseResponseStoresEmptyStringsAndZero() {
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

  /**
   * @description parserVersion is always populated regardless of input data.
   */
  @IsTest
  static void parseResponseAlwaysSetsParserVersion() {
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
