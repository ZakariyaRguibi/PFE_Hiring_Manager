@IsTest
private class InterviewStageTriggerTest {
  // ─── Test Data Setup ───────────────────────────────────────────────────

  private static Job_Position__c createPosition(String title) {
    Job_Position__c pos = new Job_Position__c(Title__c = title);
    insert pos;
    return pos;
  }

  private static Interview_Stage__c buildStage(
    Id positionId,
    Integer stageNumber
  ) {
    return new Interview_Stage__c(
      Job_Position__c = positionId,
      Stage_Number__c = stageNumber,
      Max_Score__c = 100,
      Passing_Threshold__c = 50
    );
  }

  // ─── Insert Tests ──────────────────────────────────────────────────────

  @IsTest
  static void testInsert_uniqueStageNumber_passes() {
    Job_Position__c pos = createPosition('Dev Position');

    Test.startTest();
    Interview_Stage__c stage = buildStage(pos.Id, 1);
    insert stage;
    Test.stopTest();

    System.assertNotEquals(
      null,
      stage.Id,
      'Stage should be inserted with a unique stage number'
    );
  }

  @IsTest
  static void testInsert_duplicateStageNumberSamePosition_fails() {
    Job_Position__c pos = createPosition('Dev Position');
    insert buildStage(pos.Id, 1);

    Test.startTest();
    try {
      insert buildStage(pos.Id, 1);
      System.assert(false, 'Expected DmlException for duplicate stage number');
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already exists'),
        'Error should mention duplicate stage number: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testInsert_sameStageNumberDifferentPositions_passes() {
    Job_Position__c pos1 = createPosition('Position A');
    Job_Position__c pos2 = createPosition('Position B');
    insert buildStage(pos1.Id, 1);

    Test.startTest();
    Interview_Stage__c stage2 = buildStage(pos2.Id, 1);
    insert stage2;
    Test.stopTest();

    System.assertNotEquals(
      null,
      stage2.Id,
      'Same stage number should be allowed on a different position'
    );
  }

  @IsTest
  static void testInsert_duplicateWithinBatch_fails() {
    Job_Position__c pos = createPosition('Dev Position');

    Test.startTest();
    try {
      insert new List<Interview_Stage__c>{
        buildStage(pos.Id, 1),
        buildStage(pos.Id, 1)
      };
      System.assert(
        false,
        'Expected DmlException for duplicate stage numbers in same batch'
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already exists'),
        'Error should mention duplicate: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  // ─── Update Tests ──────────────────────────────────────────────────────

  @IsTest
  static void testUpdate_changeToExistingNumber_fails() {
    Job_Position__c pos = createPosition('Dev Position');
    insert buildStage(pos.Id, 1);
    Interview_Stage__c stage2 = buildStage(pos.Id, 2);
    insert stage2;

    Test.startTest();
    try {
      stage2.Stage_Number__c = 1;
      update stage2;
      System.assert(
        false,
        'Expected DmlException when updating to a duplicate stage number'
      );
    } catch (DmlException e) {
      System.assert(
        e.getMessage().contains('already exists'),
        'Error should mention duplicate: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testUpdate_sameNumber_passes() {
    Job_Position__c pos = createPosition('Dev Position');
    Interview_Stage__c stage = buildStage(pos.Id, 1);
    insert stage;

    Test.startTest();
    stage.Max_Score__c = 200;
    update stage;
    Test.stopTest();

    Interview_Stage__c updated = [
      SELECT Max_Score__c
      FROM Interview_Stage__c
      WHERE Id = :stage.Id
    ];
    System.assertEquals(
      200,
      updated.Max_Score__c,
      'Update should succeed when stage number is unchanged'
    );
  }
}
