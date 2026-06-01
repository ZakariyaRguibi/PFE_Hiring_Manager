/**
 * @description Provider-agnostic description of an online meeting to create.
 *              Built by the caller (LWC test harness for now), consumed by a
 *              MeetingProvider implementation. Carries no provider-specific
 *              detail beyond the optional organizerIdentifier.
 */
public with sharing class MeetingRequest {
  /** @description Meeting title / subject shown in the provider UI. */
  @AuraEnabled
  public String topic;

  /** @description Free-text agenda / description (optional). */
  @AuraEnabled
  public String description;

  /** @description Meeting start. Required by every provider. */
  @AuraEnabled
  public Datetime startDateTime;

  /** @description Length in minutes. Defaults to 30 when null/<=0. */
  @AuraEnabled
  public Integer durationMinutes;

  /**
   * @description IANA / Salesforce time-zone id (e.g. "Europe/Paris").
   *              Defaults to the running user's time zone when blank.
   */
  @AuraEnabled
  public String timeZoneSidId;

  /** @description Optional invitee email addresses. */
  @AuraEnabled
  public List<String> attendeeEmails;

  /**
   * @description Whose calendar/account hosts the meeting. Provider-specific:
   *              Google = calendarId ("primary"), Zoom = userId ("me" or
   *              email), Teams = the organizer's Azure AD user id (required,
   *              since app-only auth has no "me").
   */
  @AuraEnabled
  public String organizerIdentifier;

  /** @description Convenience accessor with a safe default. */
  public Integer effectiveDuration() {
    return (durationMinutes != null && durationMinutes > 0)
      ? durationMinutes
      : 30;
  }

  /** @description End time derived from start + duration. */
  public Datetime endDateTime() {
    return startDateTime.addMinutes(effectiveDuration());
  }

  /** @description Running user's time zone when none was supplied. */
  public String effectiveTimeZone() {
    return String.isNotBlank(timeZoneSidId)
      ? timeZoneSidId
      : UserInfo.getTimeZone().getID();
  }
}
