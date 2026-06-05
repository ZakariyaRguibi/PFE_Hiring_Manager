/**
 * @description Unit tests for InterviewBotController. Covers happy path,
 *              missing meeting link, API failure, and stop flow — all via
 *              HttpCalloutMock, no live callouts.
 */
@isTest
private class InterviewBotControllerTest {
  /** @description Canned HTTP response for the Vexa callout under test. */
  private class DispatchMock implements HttpCalloutMock {
    public Integer status;
    public String body;
    public DispatchMock(Integer s, String b) {
      status = s;
      body = b;
    }
    public HttpResponse respond(HttpRequest req) {
      HttpResponse r = new HttpResponse();
      r.setStatusCode(status);
      r.setBody(body);
      r.setHeader('Content-Type', 'application/json');
      return r;
    }
  }

  private static Interview__c makeInterview(String link) {
    // Interview__c needs both Interview_Stage__c and Job_Application__c
    // (required lookups). Build the parent chain inline.
    Job_Position__c pos = new Job_Position__c(Title__c = 'Test Position');
    insert pos;
    Interview_Stage__c stage = new Interview_Stage__c(
      Job_Position__c = pos.Id,
      Stage_Number__c = 1,
      Max_Score__c = 100,
      Passing_Threshold__c = 50
    );
    insert stage;
    Candidate__c cand = new Candidate__c(
      FirstName__c = 'Test',
      LastName__c = 'Candidate',
      Email__c = 'test@example.com',
      Phone__c = '0644554253'
    );
    insert cand;
    Job_Application__c app = new Job_Application__c(
      Job_Position__c = pos.Id,
      Candidate__c = cand.Id
    );
    insert app;
    Interview__c iv = new Interview__c(
      Interview_Stage__c = stage.Id,
      Job_Application__c = app.Id,
      Meeting_Link__c = link,
      Meeting_Provider__c = 'Google Meet'
    );
    insert iv;
    return iv;
  }

  @isTest
  static void startBot_happyPath_setsCodeAndStatus() {
    Interview__c iv = makeInterview('https://meet.google.com/abc-defg-hij');
    Test.setMock(
      HttpCalloutMock.class,
      new DispatchMock(
        200,
        '{"meeting_code":"abc-defg-hij","container_id":"c123","status":"started"}'
      )
    );

    Test.startTest();
    InterviewBotController.BotActionResult r = InterviewBotController.startBot(
      iv.Id
    );
    Test.stopTest();

    System.assertEquals(true, r.success, r.message);
    System.assertEquals('abc-defg-hij', r.meetingCode);
    Interview__c after = [
      SELECT Meeting_External_Id__c, Vexa_Bot_Status__c
      FROM Interview__c
      WHERE Id = :iv.Id
    ];
    System.assertEquals('abc-defg-hij', after.Meeting_External_Id__c);
    System.assertEquals('Joining', after.Vexa_Bot_Status__c);
  }

  @isTest
  static void startBot_blankLink_returnsError() {
    Interview__c iv = makeInterview(null);
    Test.startTest();
    InterviewBotController.BotActionResult r = InterviewBotController.startBot(
      iv.Id
    );
    Test.stopTest();
    System.assertEquals(false, r.success);
    System.assert(r.message.contains('Meeting link'));
  }

  @isTest
  static void startBot_apiError_marksFailed() {
    Interview__c iv = makeInterview('https://meet.google.com/abc-defg-hij');
    Test.setMock(
      HttpCalloutMock.class,
      new DispatchMock(500, '{"error":"boom"}')
    );

    Test.startTest();
    InterviewBotController.BotActionResult r = InterviewBotController.startBot(
      iv.Id
    );
    Test.stopTest();

    System.assertEquals(false, r.success);
    Interview__c after = [
      SELECT Vexa_Bot_Status__c
      FROM Interview__c
      WHERE Id = :iv.Id
    ];
    System.assertEquals('Failed', after.Vexa_Bot_Status__c);
  }

  @isTest
  static void stopBot_happyPath_marksStopped() {
    Interview__c iv = makeInterview('https://meet.google.com/abc-defg-hij');
    iv.Meeting_External_Id__c = 'abc-defg-hij';
    iv.Vexa_Bot_Status__c = 'Recording';
    update iv;
    Test.setMock(HttpCalloutMock.class, new DispatchMock(204, ''));

    Test.startTest();
    InterviewBotController.BotActionResult r = InterviewBotController.stopBot(
      iv.Id
    );
    Test.stopTest();

    System.assertEquals(true, r.success, r.message);
    Interview__c after = [
      SELECT Vexa_Bot_Status__c
      FROM Interview__c
      WHERE Id = :iv.Id
    ];
    System.assertEquals('Stopped', after.Vexa_Bot_Status__c);
  }

  @isTest
  static void stopBot_noCode_returnsError() {
    Interview__c iv = makeInterview('https://meet.google.com/abc-defg-hij');
    Test.startTest();
    InterviewBotController.BotActionResult r = InterviewBotController.stopBot(
      iv.Id
    );
    Test.stopTest();
    System.assertEquals(false, r.success);
    System.assert(r.message.contains('No bot'));
  }
}
