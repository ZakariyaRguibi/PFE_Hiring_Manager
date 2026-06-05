/**
 * @description Thin shared HTTP helper for the meeting providers. Auth is
 *              injected by the Named Credential, so callers only build a body
 *              and an endpoint of the form "callout:<NamedCredential>/<path>".
 */
public with sharing class MeetingCallout {
  /**
   * @description Send a JSON POST and return the raw response.
   * @param endpoint full endpoint, typically "callout:Name/path"
   * @param body serialized JSON request body
   * @return the HttpResponse (status not yet checked)
   */
  public static HttpResponse postJson(String endpoint, String body) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    req.setBody(body);
    req.setTimeout(120000);
    return new Http().send(req);
  }

  /**
   * @description Throw a MeetingException unless the response is 2xx.
   * @param res the response to check
   * @param provider provider name for the error message
   */
  public static void requireSuccess(HttpResponse res, String provider) {
    Integer status = res.getStatusCode();
    if (status < 200 || status >= 300) {
      throw new MeetingException(
        provider + ' API returned HTTP ' + status + ': ' + res.getBody()
      );
    }
  }
}
