/**
 * @description Handler class for CandidateTrigger.
 *              Prevents duplicate candidate records by blocking
 *              creation if same email or phone already exists.
 *              Flags for HR review if same full name already exists.
 *
 *              Runs without sharing to ensure all existing candidates
 *              are checked regardless of the running user's visibility.
 *              This is intentional — duplicate detection must be exhaustive.
 *
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
public without sharing class CandidateTriggerHandler {
  /**
   * @description Handles before insert event.
   *              Checks for duplicate email, phone and full name.
   * @param newCandidates List of new Candidate__c records being inserted
   */
  public void onBeforeInsert(List<Candidate__c> newCandidates) {
    Set<String> emails = new Set<String>();
    Set<String> phones = new Set<String>();

    for (Candidate__c c : newCandidates) {
      if (c.Email__c != null) {
        emails.add(c.Email__c.toLowerCase());
      }
      if (c.Phone__c != null) {
        phones.add(c.Phone__c);
      }
    }

    Map<String, Boolean> emailMap = buildEmailMap(emails);
    Map<String, Boolean> phoneMap = buildPhoneMap(phones);
    Set<String> nameSet = buildNameSet();

    for (Candidate__c c : newCandidates) {
      if (
        c.Email__c != null && emailMap.containsKey(c.Email__c.toLowerCase())
      ) {
        c.addError('A candidate with this email already exists in the system.');
      }
      if (c.Phone__c != null && phoneMap.containsKey(c.Phone__c)) {
        c.addError(
          'A candidate with this phone number already exists in the system.'
        );
      }
      if (c.FirstName__c != null && c.LastName__c != null) {
        String fullName = (c.FirstName__c + ' ' + c.LastName__c).toLowerCase();
        if (nameSet.contains(fullName)) {
          c.Duplicate_Flag__c = true;
          c.Duplicate_Review_Status__c = 'Pending';
        }
      }
    }
  }

  /**
   * @description Queries existing candidates by email and builds a lookup map
   * @param emails Set of email addresses to check
   * @return Map<String, Boolean> map of lowercase email to true
   */
  private Map<String, Boolean> buildEmailMap(Set<String> emails) {
    Map<String, Boolean> emailMap = new Map<String, Boolean>();
    if (emails.isEmpty()) {
      return emailMap;
    }
    for (Candidate__c c : [
      SELECT Id, Email__c
      FROM Candidate__c
      WHERE Email__c IN :emails
    ]) {
      emailMap.put(c.Email__c.toLowerCase(), true);
    }
    return emailMap;
  }

  /**
   * @description Queries existing candidates by phone and builds a lookup map
   * @param phones Set of phone numbers to check
   * @return Map<String, Boolean> map of phone to true
   */
  private Map<String, Boolean> buildPhoneMap(Set<String> phones) {
    Map<String, Boolean> phoneMap = new Map<String, Boolean>();
    if (phones.isEmpty()) {
      return phoneMap;
    }
    for (Candidate__c c : [
      SELECT Id, Phone__c
      FROM Candidate__c
      WHERE Phone__c IN :phones
    ]) {
      phoneMap.put(c.Phone__c, true);
    }
    return phoneMap;
  }

  /**
   * @description Queries all existing candidates with names and builds a name set
   * @return Set<String> set of lowercase full names
   */
  private Set<String> buildNameSet() {
    Set<String> nameSet = new Set<String>();
    for (Candidate__c c : [
      SELECT Id, FirstName__c, LastName__c
      FROM Candidate__c
      WHERE FirstName__c != NULL AND LastName__c != NULL
    ]) {
      nameSet.add((c.FirstName__c + ' ' + c.LastName__c).toLowerCase());
    }
    return nameSet;
  }
}
