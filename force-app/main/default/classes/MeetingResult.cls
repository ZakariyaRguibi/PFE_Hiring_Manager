/**
 * @description Normalized result of creating a meeting on any provider.
 *              Returned to the caller and used to stamp the Interview record.
 */
public with sharing class MeetingResult {
  /** @description The join URL participants open to enter the meeting. */
  @AuraEnabled
  public String joinUrl;

  /** @description Provider-side id (event / meeting id) for later cancel. */
  @AuraEnabled
  public String externalMeetingId;

  /** @description Display name of the provider that created it. */
  @AuraEnabled
  public String provider;

  /** @description Raw provider JSON, kept for debugging the test harness. */
  @AuraEnabled
  public String rawResponse;

  public MeetingResult() {
  }

  public MeetingResult(
    String provider,
    String joinUrl,
    String externalMeetingId
  ) {
    this.provider = provider;
    this.joinUrl = joinUrl;
    this.externalMeetingId = externalMeetingId;
  }
}
