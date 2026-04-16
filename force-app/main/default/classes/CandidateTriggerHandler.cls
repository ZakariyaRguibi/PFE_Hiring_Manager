/**
 * @description Handler class for CandidateTrigger.
 *              Prevents duplicate candidate records by blocking
 *              creation if same email or phone already exists.
 *              Flags for HR review if same full name already exists.
 *
 * @author Hiba Balhirch
 * @date 2026-04-14
 */
public without sharing class CandidateTriggerHandler {

    /**
     * @description Handles before insert event.
     *              Checks for duplicate email, phone and full name.
     *              Runs without sharing to ensure all existing candidates
     *              are checked regardless of the running user's visibility.
     *              This is intentional — duplicate detection must be exhaustive.
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
            WHERE FirstName__c != null
            AND LastName__c != null
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
            nameSet.add((c.FirstName__c + ' ' + c.LastName__c).toLowerCase());
        }

        for (Candidate__c c : newCandidates) {
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
}