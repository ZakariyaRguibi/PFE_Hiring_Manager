public class CandidateCommunityUserProvisioner implements Queueable {

    private Set<Id> contactIds;

    public CandidateCommunityUserProvisioner(Set<Id> contactIds) {
        this.contactIds = contactIds;
    }

    public void execute(QueueableContext context) {

        // 1) Get the Experience profile (adjust the name if yours is different)
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Customer Community Login User'
            LIMIT 1
        ];

        // 2) Load contacts + their accounts
        List<Contact> contacts = [
            SELECT Id, Email, FirstName, LastName, AccountId
            FROM Contact
            WHERE Id IN :contactIds
              AND Email != null
              AND AccountId != null
        ];

        if (contacts.isEmpty()) return;

        // 3) Avoid duplicates: existing users already linked to these contacts
        Map<Id, User> existingByContact = new Map<Id, User>();
        for (User u : [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId IN :contactIds
        ]) {
            existingByContact.put(u.ContactId, u);
        }

        List<User> usersToInsert = new List<User>();

        for (Contact c : contacts) {
            if (existingByContact.containsKey(c.Id)) continue;

            String emailLower = c.Email.trim().toLowerCase();

            // Username must be globally unique across all Salesforce orgs.
            // We add OrgId to make it unique.
            String uniqueUsername = emailLower + '.' + UserInfo.getOrganizationId() + '.candidate';

            // Alias max 8 chars
            String aliasVal = (c.LastName == null ? 'cand' : c.LastName);
            aliasVal = aliasVal.replaceAll('[^A-Za-z0-9]', '');
            if (aliasVal.length() > 8) aliasVal = aliasVal.substring(0, 8);
            if (aliasVal.length() < 2) aliasVal = 'cand';

            // CommunityNickname must be unique in the org
            String nick = (c.FirstName == null ? 'cand' : c.FirstName) + (c.LastName == null ? '' : c.LastName);
            nick = nick.replaceAll('[^A-Za-z0-9]', '');
            if (nick.length() < 3) nick = 'cand' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
            if (nick.length() > 40) nick = nick.substring(0, 40);

            User u = new User();
            u.ProfileId = p.Id;
            u.ContactId = c.Id;
            u.Email = emailLower;
            u.Username = uniqueUsername;
            u.LastName = (c.LastName == null ? 'Candidate' : c.LastName);
            u.Alias = aliasVal;
            u.CommunityNickname = nick;

            // Required user settings
            u.TimeZoneSidKey = 'Africa/Casablanca';
            u.LocaleSidKey = 'fr_FR';
            u.EmailEncodingKey = 'UTF-8';
            u.LanguageLocaleKey = 'fr';

            u.IsActive = true;

            usersToInsert.add(u);
        }

        if (usersToInsert.isEmpty()) return;

        insert usersToInsert;

        // 4) Send password email (BEST for Experience Cloud)
        // This sends a reset-password email (safe + standard).
        for (User u : usersToInsert) {
            System.resetPassword(u.Id, true);
        }
    }
}