/**
 * @description Unit tests for the meeting-creation feature. Covers Google Meet
 *              request building + response parsing (via HttpCalloutMock), the
 *              dispatcher, Interview stamping, and the error paths. No live
 *              callouts are made. The architecture is provider-agnostic; only
 *              Google Meet is wired today.
 */
@IsTest
private class MeetingServiceTest {
  /**
   * @description Returns a canned Google Calendar response and records the last
   *              request so tests can assert what was sent.
   */
  private class GoogleMock implements HttpCalloutMock {
    public String lastEndpoint;
    public String lastBody;
    public String lastMethod;
    private Boolean omitHangoutLink = false;

    public GoogleMock() {
    }
    public GoogleMock(Boolean omitHangoutLink) {
      this.omitHangoutLink = omitHangoutLink;
    }

    public HttpResponse respond(HttpRequest req) {
      lastEndpoint = req.getEndpoint();
      lastBody = req.getBody();
      lastMethod = req.getMethod();

      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(200);
      res.setBody(body());
      return res;
    }

    private String body() {
      if (omitHangoutLink) {
        return '{"id":"evt-1","conferenceData":{"entryPoints":[' +
          '{"entryPointType":"more","uri":"https://meet.google.com/info"},' +
          '{"entryPointType":"video","uri":"https://meet.google.com/abc-defg-hij"}]}}';
      }
      return '{"id":"evt-1","hangoutLink":"https://meet.google.com/abc-defg-hij",' +
        '"conferenceData":{"entryPoints":[{"entryPointType":"video",' +
        '"uri":"https://meet.google.com/abc-defg-hij"}]}}';
    }
  }

  /** @description Always returns a non-2xx error for the error-path test. */
  private class ErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(400);
      res.setBody('{"error":{"message":"bad request"}}');
      return res;
    }
  }

  private static Interview__c createInterview() {
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
    Interview__c interviewRec = new Interview__c(
      Interview_Stage__c = stage.Id,
      Job_Application__c = app.Id
    );
    insert interviewRec;
    return interviewRec;
  }

  private static MeetingRequest sampleRequest(String organizer) {
    MeetingRequest req = new MeetingRequest();
    req.topic = 'Round 1 Interview';
    req.description = 'Technical screen';
    req.startDateTime = Datetime.newInstanceGmt(2026, 6, 1, 14, 0, 0);
    req.durationMinutes = 45;
    req.timeZoneSidId = 'Europe/Paris';
    req.organizerIdentifier = organizer;
    req.attendeeEmails = new List<String>{ 'a@example.com', 'b@example.com' };
    return req;
  }

  @IsTest
  static void googleMeetCreatesMeeting() {
    GoogleMock mock = new GoogleMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    MeetingResult result = MeetingService.createMeeting(
      sampleRequest(null),
      MeetingService.GOOGLE_MEET
    );
    Test.stopTest();

    System.assertEquals('Google Meet', result.provider, 'provider name');
    System.assertEquals(
      'https://meet.google.com/abc-defg-hij',
      result.joinUrl,
      'join url from hangoutLink'
    );
    System.assertEquals('evt-1', result.externalMeetingId, 'event id');
    System.assert(
      mock.lastEndpoint.contains('/calendars/primary/events'),
      'defaults to primary calendar: ' + mock.lastEndpoint
    );
    System.assert(
      mock.lastEndpoint.contains('conferenceDataVersion=1'),
      'requests conference data'
    );
    System.assert(
      mock.lastBody.contains('hangoutsMeet'),
      'asks for a Meet conference'
    );
    System.assert(mock.lastBody.contains('attendees'), 'includes attendees');
  }

  @IsTest
  static void googleMeetFallsBackToEntryPoint() {
    Test.setMock(HttpCalloutMock.class, new GoogleMock(true));

    Test.startTest();
    MeetingResult result = new GoogleMeetProvider()
      .createMeeting(sampleRequest('me@org.com'));
    Test.stopTest();

    System.assertEquals(
      'https://meet.google.com/abc-defg-hij',
      result.joinUrl,
      'falls back to video entryPoint when no hangoutLink'
    );
  }

  @IsTest
  static void generateMeetingStampsInterview() {
    Interview__c interviewRec = createInterview();
    Test.setMock(HttpCalloutMock.class, new GoogleMock());

    Test.startTest();
    MeetingResult result = MeetingService.generateMeeting(
      'Google Meet',
      'Interview with candidate',
      '2026-06-01T14:00:00Z',
      30,
      'Europe/Paris',
      'a@example.com, b@example.com',
      null,
      interviewRec.Id
    );
    Test.stopTest();

    Interview__c reloaded = [
      SELECT Meeting_Provider__c, Meeting_Link__c, Meeting_External_Id__c
      FROM Interview__c
      WHERE Id = :interviewRec.Id
    ];
    System.assertEquals(
      'Google Meet',
      reloaded.Meeting_Provider__c,
      'provider stamped'
    );
    System.assertEquals(
      result.joinUrl,
      reloaded.Meeting_Link__c,
      'link stamped'
    );
    System.assertEquals(
      'evt-1',
      reloaded.Meeting_External_Id__c,
      'external id stamped'
    );
  }

  @IsTest
  static void generateMeetingWrapsErrorsForLwc() {
    Test.setMock(HttpCalloutMock.class, new ErrorMock());
    Boolean thrown = false;
    Test.startTest();
    try {
      MeetingService.generateMeeting(
        'Google Meet',
        'X',
        '2026-06-01T14:00:00Z',
        30,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException e) {
      thrown = true;
    }
    Test.stopTest();
    System.assert(
      thrown,
      'non-2xx is surfaced to the LWC as AuraHandledException'
    );
  }

  @IsTest
  static void unknownProviderThrows() {
    Boolean thrown = false;
    try {
      MeetingService.createMeeting(sampleRequest(null), 'Webex');
    } catch (MeetingException e) {
      thrown = true;
      System.assert(
        e.getMessage().contains('Unknown'),
        'names the bad provider'
      );
    }
    System.assert(thrown, 'unknown provider must throw');
  }

  @IsTest
  static void missingStartThrows() {
    MeetingRequest req = new MeetingRequest();
    req.topic = 'no start';
    Boolean thrown = false;
    try {
      MeetingService.createMeeting(req, MeetingService.GOOGLE_MEET);
    } catch (MeetingException e) {
      thrown = true;
    }
    System.assert(thrown, 'missing start date/time must throw');
  }

  @IsTest
  static void dispatcherAcceptsAliases() {
    System.assertEquals(
      'Google Meet',
      MeetingService.resolveProvider('meet').providerName(),
      'meet alias'
    );
    System.assertEquals(
      'Google Meet',
      MeetingService.resolveProvider(' GOOGLE ').providerName(),
      'trim + case-insensitive'
    );
  }

  @IsTest
  static void helpersBehave() {
    System.assertEquals(
      3,
      MeetingService.splitEmails('a@x.com, b@x.com; c@x.com').size(),
      'splits on comma/semicolon/space'
    );
    System.assertEquals(
      0,
      MeetingService.splitEmails(null).size(),
      'null -> empty'
    );
    System.assertEquals(null, MeetingService.parseIso('  '), 'blank -> null');
    System.assertNotEquals(
      null,
      MeetingService.parseIso('2026-06-01T14:00:00Z'),
      'parses ISO'
    );

    MeetingRequest req = new MeetingRequest();
    req.startDateTime = Datetime.newInstanceGmt(2026, 6, 1, 14, 0, 0);
    System.assertEquals(30, req.effectiveDuration(), 'default duration');
    System.assertEquals(
      req.startDateTime.addMinutes(30),
      req.endDateTime(),
      'end = start + duration'
    );
    System.assert(String.isNotBlank(req.effectiveTimeZone()), 'tz defaults');
  }
}
