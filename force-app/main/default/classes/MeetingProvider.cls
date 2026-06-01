/**
 * @description Strategy contract for an online-meeting provider. A concrete
 *              provider turns a MeetingRequest into a normalized MeetingResult
 *              by calling its own REST API through a Named Credential.
 *              MeetingService selects the implementation. Google Meet is the
 *              only provider wired today; adding Zoom/Teams means implementing
 *              this interface and adding one branch to MeetingService.
 */
public interface MeetingProvider {
  /**
   * @description Create the meeting on the remote provider.
   * @param request provider-agnostic meeting details
   * @return normalized result with the join URL + external id
   * @throws MeetingException on any failure
   */
  MeetingResult createMeeting(MeetingRequest request);

  /** @description Display name, matching the Interview picklist value. */
  String providerName();
}
