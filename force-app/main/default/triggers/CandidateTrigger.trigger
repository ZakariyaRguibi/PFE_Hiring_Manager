/**
 * @description Trigger on Candidate__c to prevent duplicate candidate records.
 *              Blocks creation if same email or phone already exists.
 *              Flags for HR review if same full name already exists.
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
trigger CandidateTrigger on Candidate__c (before insert) {

    Set<String> emails = new Set<String>();
    Set<String> phones = new Set<String>();

    for (Candidate__c c : Trigger.new) {
        if (c.Email__c != null) emails.add(c.Email__c.toLowerCase());
        if (c.Phone__c != null) phones.add(c.Phone__c);
    }

    List<Candidate__c> existingByEmail = [
        SELECT Id, Email__c
        FROM Candidate__c
        WHERE Email__c IN :emails
    ];

    List<Candidate__c> existingByPhone = [
        SELECT Id, Phone__c
        FROM Candidate__c
        WHERE Phone__c IN :phones
    ];

    List<Candidate__c> existingByName = [
        SELECT Id, FirstName__c, LastName__c
        FROM Candidate__c
    ];

    Map<String, Boolean> emailMap = new Map<String, Boolean>();
    for (Candidate__c c : existingByEmail) {
        emailMap.put(c.Email__c.toLowerCase(), true);
    }

    Map<String, Boolean> phoneMap = new Map<String, Boolean>();
    for (Candidate__c c : existingByPhone) {
        phoneMap.put(c.Phone__c, true);
    }

    Set<String> nameSet = new Set<String>();
    for (Candidate__c c : existingByName) {
        if (c.FirstName__c != null && c.LastName__c != null) {
            nameSet.add((c.FirstName__c + ' ' + c.LastName__c).toLowerCase());
        }
    }

    for (Candidate__c c : Trigger.new) {

        if (c.Email__c != null && emailMap.containsKey(c.Email__c.toLowerCase())) {
            c.addError('A candidate with this email already exists in the system.');
        }

        if (c.Phone__c != null && phoneMap.containsKey(c.Phone__c)) {
            c.addError('A candidate with this phone number already exists in the system.');
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