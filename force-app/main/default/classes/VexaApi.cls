/**
 * @description Thin HTTP wrapper around the meeting-assistant API.
 *              Auth + base URL are provided by the `Vexa_Api` Named Credential
 *              (set the bearer token in the credential's principal — the
 *              `Authorization` header is added automatically as
 *              `Bearer {!$Credential.Password}`).
 *              All callouts go to: callout:Vexa_Api/api/...
 */
public with sharing class VexaApi {
  /** @description Raised when the meeting-assistant API returns an error. */
  public class VexaException extends Exception {
  }

  /** @description Normalized response from a successful bot dispatch. */
  public class DispatchResult {
    /** @description Provider-side meeting code, used to stop the bot later. */
    public String meetingCode;
    /** @description Container id assigned by the bot runtime. */
    public String containerId;
    /** @description Full raw JSON body, kept for debugging. */
    public String rawBody;
  }

  /**
   * @description POST /api/meetings — dispatch a bot to the given Meet URL.
   *              `externalRef` is the Interview__c.Id so the webhook receiver
   *              can push results back to the right record.
   * @param meetUrl join URL of the meeting the bot should attend
   * @param externalRef opaque reference echoed back by the webhook (Interview Id)
   * @return normalized result with the meeting code + container id
   * @throws VexaException on missing input or non-2xx HTTP response
   */
  public static DispatchResult dispatch(String meetUrl, String externalRef) {
    if (String.isBlank(meetUrl)) {
      throw new VexaException('meetUrl is required');
    }
    Map<String, Object> body = new Map<String, Object>{
      'url' => meetUrl,
      'external_ref' => externalRef
    };
    HttpResponse res = send('POST', '/api/meetings', JSON.serialize(body));
    if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
      throw new VexaException(
        'dispatch failed: HTTP ' + res.getStatusCode() + ' ' + res.getBody()
      );
    }
    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      res.getBody()
    );
    DispatchResult r = new DispatchResult();
    // Our api returns both `meeting_code` and `code` carrying the same value;
    // accept either to stay tolerant of small response shape changes.
    Object mc = parsed.get('meeting_code');
    if (mc == null)
      mc = parsed.get('code');
    r.meetingCode = (String) mc;
    r.containerId = (String) parsed.get('container_id');
    r.rawBody = res.getBody();
    return r;
  }

  /**
   * @description DELETE /api/meetings/:code — stop the bot. Best effort;
   *              treats 404 as success (already gone).
   * @param meetingCode provider-side code returned by dispatch()
   * @throws VexaException on missing input or non-2xx/404 HTTP response
   */
  public static void stop(String meetingCode) {
    if (String.isBlank(meetingCode)) {
      throw new VexaException('meetingCode is required');
    }
    HttpResponse res = send(
      'DELETE',
      '/api/meetings/' + EncodingUtil.urlEncode(meetingCode, 'UTF-8'),
      null
    );
    Integer code = res.getStatusCode();
    if (code != 200 && code != 202 && code != 204 && code != 404) {
      throw new VexaException(
        'stop failed: HTTP ' + code + ' ' + res.getBody()
      );
    }
  }

  /**
   * @description Shared HTTP send for the Vexa Named Credential.
   * @param method HTTP method (GET/POST/DELETE/…)
   * @param path path appended to the credential's base URL
   * @param jsonBody serialized JSON body, or null for no body
   * @return the raw HttpResponse (status not yet checked)
   */
  private static HttpResponse send(
    String method,
    String path,
    String jsonBody
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:Vexa_Api' + path);
    req.setMethod(method);
    req.setTimeout(60000);
    req.setHeader('Accept', 'application/json');
    if (jsonBody != null) {
      req.setHeader('Content-Type', 'application/json');
      req.setBody(jsonBody);
    }
    return new Http().send(req);
  }
}
