/**
 * @description Entry point and dispatcher for online-meeting creation. Resolves
 *              the requested provider, delegates the callout, and (optionally)
 *              stamps the result onto an Interview record.
 *
 *              The @AuraEnabled generateMeeting() takes primitives so the LWC
 *              test harness never has to marshal an Apex object; createMeeting()
 *              is the typed Apex-facing API.
 */
public with sharing class MeetingService {
  /** @description Picklist / providerName() values, exposed for the LWC. */
  public static final String GOOGLE_MEET = 'Google Meet';

  /**
   * @description LWC-facing creation. Builds a MeetingRequest from primitives,
   *              creates the meeting, and stamps the Interview when an id is
   *              supplied.
   * @param provider one of "Google Meet" | "Zoom" | "Microsoft Teams"
   * @param topic meeting title
   * @param startDateTimeIso ISO-8601 start (e.g. from a datetime input)
   * @param durationMinutes length in minutes (null/<=0 -> 30)
   * @param timeZoneSidId IANA tz id (blank -> running user's tz)
   * @param attendeeEmails comma/newline separated invitee emails (optional)
   * @param organizerIdentifier calendar/user/organizer id (provider-specific)
   * @param interviewId Interview__c to stamp (optional)
   * @return the normalized MeetingResult
   */
  @AuraEnabled
  public static MeetingResult generateMeeting(
    String provider,
    String topic,
    String startDateTimeIso,
    Integer durationMinutes,
    String timeZoneSidId,
    String attendeeEmails,
    String organizerIdentifier,
    Id interviewId
  ) {
    try {
      MeetingRequest request = new MeetingRequest();
      request.topic = topic;
      request.startDateTime = parseIso(startDateTimeIso);
      request.durationMinutes = durationMinutes;
      request.timeZoneSidId = timeZoneSidId;
      request.organizerIdentifier = organizerIdentifier;
      request.attendeeEmails = splitEmails(attendeeEmails);

      MeetingResult result = createMeeting(request, provider);

      if (interviewId != null) {
        stampInterview(interviewId, result);
      }
      return result;
    } catch (MeetingException me) {
      throw new AuraHandledException(me.getMessage());
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not create meeting: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Typed Apex API: create a meeting on the named provider.
   * @param request meeting details
   * @param provider provider display name
   * @return normalized result
   */
  public static MeetingResult createMeeting(
    MeetingRequest request,
    String provider
  ) {
    if (request == null || request.startDateTime == null) {
      throw new MeetingException('A meeting start date/time is required.');
    }
    return resolveProvider(provider).createMeeting(request);
  }

  /**
   * @description Map a provider name to its implementation. This switch is the
   *              single extension point: adding Zoom/Teams later means writing a
   *              new MeetingProvider class and adding one branch here — nothing
   *              else in the feature changes.
   * @param provider provider display name
   * @return the MeetingProvider strategy
   */
  @TestVisible
  private static MeetingProvider resolveProvider(String provider) {
    String key = (provider == null) ? '' : provider.trim().toLowerCase();
    switch on key {
      when 'google meet', 'google', 'meet' {
        return new GoogleMeetProvider();
      }
      when else {
        throw new MeetingException('Unknown meeting provider: ' + provider);
      }
    }
  }

  @TestVisible
  private static void stampInterview(Id interviewId, MeetingResult result) {
    Interview__c record = new Interview__c(Id = interviewId);
    record.Meeting_Provider__c = result.provider;
    record.Meeting_Link__c = result.joinUrl;
    record.Meeting_External_Id__c = result.externalMeetingId;
    update record;
  }

  @TestVisible
  private static Datetime parseIso(String iso) {
    if (String.isBlank(iso)) {
      return null;
    }
    // JSON parsing handles ISO-8601 (with/without offset) robustly.
    return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
  }

  @TestVisible
  private static List<String> splitEmails(String raw) {
    List<String> emails = new List<String>();
    if (String.isBlank(raw)) {
      return emails;
    }
    for (String part : raw.split('[,;\\s]+')) {
      if (String.isNotBlank(part)) {
        emails.add(part.trim());
      }
    }
    return emails;
  }
}
