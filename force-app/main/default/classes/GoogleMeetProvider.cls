/**
 * @description Creates a Google Meet link by inserting a Google Calendar event
 *              with an attached conference. The Meet URL is minted by Google as
 *              a side effect of the event's conferenceData.createRequest.
 *
 *              Auth: Named Credential "GoogleMeet" (OAuth2 authorization-code,
 *              Named Principal) pointing at https://www.googleapis.com. The
 *              connected Google account owns the target calendar.
 *
 *              Docs: Calendar API events.insert with conferenceDataVersion=1.
 */
public with sharing class GoogleMeetProvider implements MeetingProvider {
  @TestVisible
  private static final String NAMED_CREDENTIAL = 'GoogleMeet';

  public String providerName() {
    return 'Google Meet';
  }

  public MeetingResult createMeeting(MeetingRequest request) {
    String calendarId = String.isNotBlank(request.organizerIdentifier)
      ? request.organizerIdentifier
      : 'primary';
    String tz = request.effectiveTimeZone();

    String endpoint =
      'callout:' +
      NAMED_CREDENTIAL +
      '/calendar/v3/calendars/' +
      EncodingUtil.urlEncode(calendarId, 'UTF-8') +
      '/events?conferenceDataVersion=1';

    String body = buildBody(request, tz);
    HttpResponse res = MeetingCallout.postJson(endpoint, body);
    MeetingCallout.requireSuccess(res, providerName());

    return parse(res.getBody());
  }

  @TestVisible
  private String buildBody(MeetingRequest request, String tz) {
    JSONGenerator gen = JSON.createGenerator(false);
    gen.writeStartObject();
    gen.writeStringField('summary', stringOr(request.topic, 'Interview'));
    if (String.isNotBlank(request.description)) {
      gen.writeStringField('description', request.description);
    }

    gen.writeFieldName('start');
    gen.writeStartObject();
    gen.writeStringField(
      'dateTime',
      request.startDateTime.format('yyyy-MM-dd\'T\'HH:mm:ss', tz)
    );
    gen.writeStringField('timeZone', tz);
    gen.writeEndObject();

    gen.writeFieldName('end');
    gen.writeStartObject();
    gen.writeStringField(
      'dateTime',
      request.endDateTime().format('yyyy-MM-dd\'T\'HH:mm:ss', tz)
    );
    gen.writeStringField('timeZone', tz);
    gen.writeEndObject();

    if (request.attendeeEmails != null && !request.attendeeEmails.isEmpty()) {
      gen.writeFieldName('attendees');
      gen.writeStartArray();
      for (String email : request.attendeeEmails) {
        if (String.isBlank(email)) {
          continue;
        }
        gen.writeStartObject();
        gen.writeStringField('email', email.trim());
        gen.writeEndObject();
      }
      gen.writeEndArray();
    }

    gen.writeFieldName('conferenceData');
    gen.writeStartObject();
    gen.writeFieldName('createRequest');
    gen.writeStartObject();
    // Idempotency key for the conference creation.
    gen.writeStringField('requestId', generateRequestId());
    gen.writeFieldName('conferenceSolutionKey');
    gen.writeStartObject();
    gen.writeStringField('type', 'hangoutsMeet');
    gen.writeEndObject();
    gen.writeEndObject();
    gen.writeEndObject();

    gen.writeEndObject();
    return gen.getAsString();
  }

  @TestVisible
  private MeetingResult parse(String responseBody) {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );

    String joinUrl = (String) root.get('hangoutLink');
    // Fallback: dig the video entry point out of conferenceData.
    if (String.isBlank(joinUrl)) {
      joinUrl = extractVideoEntryPoint(root);
    }
    if (String.isBlank(joinUrl)) {
      throw new MeetingException(
        'Google response had no Meet link (hangoutLink/entryPoints). Body: ' +
        responseBody
      );
    }

    MeetingResult result = new MeetingResult(
      providerName(),
      joinUrl,
      (String) root.get('id')
    );
    result.rawResponse = responseBody;
    return result;
  }

  private String extractVideoEntryPoint(Map<String, Object> root) {
    Object conf = root.get('conferenceData');
    if (!(conf instanceof Map<String, Object>)) {
      return null;
    }
    Object entries = ((Map<String, Object>) conf).get('entryPoints');
    if (!(entries instanceof List<Object>)) {
      return null;
    }
    for (Object entry : (List<Object>) entries) {
      Map<String, Object> ep = (Map<String, Object>) entry;
      if ('video'.equals(ep.get('entryPointType'))) {
        return (String) ep.get('uri');
      }
    }
    return null;
  }

  private String generateRequestId() {
    return 'tf-' + Crypto.getRandomLong() + '-' + DateTime.now().getTime();
  }

  private String stringOr(String value, String fallback) {
    return String.isNotBlank(value) ? value : fallback;
  }
}
