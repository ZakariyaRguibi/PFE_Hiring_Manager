/**
 * @description Raised when a provider cannot create a meeting (bad config,
 *              auth failure, non-2xx response, unparseable body, etc.).
 */
public with sharing class MeetingException extends Exception {
}
