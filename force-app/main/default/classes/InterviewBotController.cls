/**
 * @description Aura/LWC-callable controller for the "Start Bot" / "Stop Bot"
 *              quick actions on Interview__c. Thin glue around VexaApi — does
 *              the callout, writes back the meeting code + bot status, and
 *              surfaces errors to the UI.
 */
public with sharing class InterviewBotController {
  /** @description Normalized result returned to the LWC for both actions. */
  public class BotActionResult {
    /** @description True when the action succeeded end-to-end. */
    @AuraEnabled
    public Boolean success;
    /** @description Provider-side meeting code (when known). */
    @AuraEnabled
    public String meetingCode;
    /** @description Human-readable status / error message for the toast. */
    @AuraEnabled
    public String message;
  }

  /**
   * @description Dispatch a recording bot to the Interview's Meeting_Link__c,
   *              then stamp the meeting code + status onto the record.
   * @param interviewId Interview__c the bot should join
   * @return success flag, meeting code, and a UI-ready message
   */
  @AuraEnabled
  public static BotActionResult startBot(Id interviewId) {
    BotActionResult out = new BotActionResult();
    Interview__c iv = loadInterview(interviewId);

    if (String.isBlank(iv.Meeting_Link__c)) {
      out.success = false;
      out.message = 'Meeting link is empty on this interview.';
      return out;
    }
    if (
      iv.Vexa_Bot_Status__c == 'Recording' ||
      iv.Vexa_Bot_Status__c == 'Joining'
    ) {
      out.success = false;
      out.message =
        'Bot is already ' +
        iv.Vexa_Bot_Status__c.toLowerCase() +
        '.';
      return out;
    }

    try {
      VexaApi.DispatchResult r = VexaApi.dispatch(iv.Meeting_Link__c, iv.Id);
      iv.Meeting_External_Id__c = r.meetingCode;
      iv.Vexa_Bot_Status__c = 'Joining';
      Database.update(iv, AccessLevel.SYSTEM_MODE);
      out.success = true;
      out.meetingCode = r.meetingCode;
      out.message = 'Bot dispatched. It will appear in the Meet lobby shortly.';
    } catch (Exception e) {
      iv.Vexa_Bot_Status__c = 'Failed';
      Database.update(iv, AccessLevel.SYSTEM_MODE);
      out.success = false;
      out.message = 'Dispatch failed: ' + e.getMessage();
    }
    return out;
  }

  /**
   * @description Ask the bot to leave the meeting and mark the record stopped.
   * @param interviewId Interview__c whose bot should be stopped
   * @return success flag, meeting code, and a UI-ready message
   */
  @AuraEnabled
  public static BotActionResult stopBot(Id interviewId) {
    BotActionResult out = new BotActionResult();
    Interview__c iv = loadInterview(interviewId);

    if (String.isBlank(iv.Meeting_External_Id__c)) {
      out.success = false;
      out.message = 'No bot has been dispatched for this interview yet.';
      return out;
    }

    try {
      VexaApi.stop(iv.Meeting_External_Id__c);
      iv.Vexa_Bot_Status__c = 'Stopped';
      Database.update(iv, AccessLevel.SYSTEM_MODE);
      out.success = true;
      out.meetingCode = iv.Meeting_External_Id__c;
      out.message = 'Bot stop requested.';
    } catch (Exception e) {
      out.success = false;
      out.message = 'Stop failed: ' + e.getMessage();
    }
    return out;
  }

  /**
   * @description Load the bot-relevant fields from one Interview, enforcing
   *              record-level visibility (the empty-result branch surfaces a
   *              clear FLS/sharing hint to the caller).
   * @param id Interview__c record id
   * @return the Interview record with bot fields populated
   * @throws VexaApi.VexaException when the record isn't visible to the user
   */
  private static Interview__c loadInterview(Id id) {
    List<Interview__c> rows = [
      SELECT Id, Meeting_Link__c, Meeting_External_Id__c, Vexa_Bot_Status__c
      FROM Interview__c
      WHERE Id = :id
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new VexaApi.VexaException(
        'Interview ' +
          id +
          ' not visible to ' +
          UserInfo.getUserName() +
          ' — check Field-Level Security on Vexa_* fields and record sharing.'
      );
    }
    return rows[0];
  }
}
