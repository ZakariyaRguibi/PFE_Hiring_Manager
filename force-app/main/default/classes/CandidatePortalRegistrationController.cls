/**
 * @description Controller used by the TalentForce Candidate Portal self-registration form.
 * It creates an External Identity user account, sets the password chosen by the candidate,
 * and asynchronously creates the related Candidate__c profile.
 *
 * The class runs without sharing intentionally because guest users must be able to start
 * the registration process before they own any Salesforce records.
 */
public without sharing class CandidatePortalRegistrationController {
  private static final String EXTERNAL_IDENTITY_PROFILE_NAME = 'External Identity User';
  private static final String EXTERNAL_IDENTITY_LICENSE_NAME = 'External Identity';

  /**
   * @description Result returned to the registration form after account creation.
   */
  public class RegistrationResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public Id userId;
  }

  /**
   * @description Registers a new candidate portal user and schedules candidate profile creation.
   * @param firstName Candidate first name.
   * @param lastName Candidate last name.
   * @param email Candidate email, also used as username.
   * @param phone Candidate phone number.
   * @param educationLevel Candidate education level.
   * @param yearsOfExperience Candidate years of experience.
   * @param password Password chosen by the candidate.
   * @param confirmPassword Password confirmation.
   * @return Registration result containing success status, message, username, and created user id.
   */
  @AuraEnabled
  public static RegistrationResult registerCandidate(
    String firstName,
    String lastName,
    String email,
    String phone,
    String educationLevel,
    Decimal yearsOfExperience,
    String password,
    String confirmPassword
  ) {
    RegistrationResult result = new RegistrationResult();
    result.success = false;

    validateInput(
      firstName,
      lastName,
      email,
      phone,
      educationLevel,
      yearsOfExperience,
      password,
      confirmPassword
    );

    String normalizedEmail = email.trim().toLowerCase();
    String normalizedPhone = phone != null ? phone.trim() : null;

    ensureNoExistingUser(normalizedEmail);
    ensureNoExistingCandidate(normalizedEmail, normalizedPhone);

        Profile externalIdentityProfile = getExternalIdentityProfile();

        if (!Schema.sObjectType.User.isCreateable()) {
            throw new AuraHandledException(
                'User creation is not allowed for the current context. Please contact an administrator.'
            );
        }

    User newUser = new User(
      FirstName = firstName.trim(),
      LastName = lastName.trim(),
      Email = normalizedEmail,
      Username = normalizedEmail,
      Alias = buildAlias(firstName, lastName),
      CommunityNickname = buildCommunityNickname(firstName, lastName),
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = externalIdentityProfile.Id,
      IsActive = true
    );

        insert newUser;

    System.setPassword(newUser.Id, password);

    System.enqueueJob(
      new CandidateCreationJob(
        newUser.Id,
        firstName.trim(),
        lastName.trim(),
        normalizedEmail,
        normalizedPhone,
        educationLevel,
        yearsOfExperience
      )
    );

    result.success = true;
    result.message = 'Account created successfully. You can now log in.';
    result.username = normalizedEmail;
    result.userId = newUser.Id;

    return result;
  }

    /**
     * @description Validates the registration form input before user creation.
     * @param firstName Candidate first name.
     * @param lastName Candidate last name.
     * @param email Candidate email.
     * @param phone Candidate phone number.
     * @param educationLevel Candidate education level.
     * @param yearsOfExperience Candidate years of experience.
     * @param password Candidate password.
     * @param confirmPassword Candidate password confirmation.
     */
    private static void validateInput(
        String firstName,
        String lastName,
        String email,
        String phone,
        String educationLevel,
        Decimal yearsOfExperience,
        String password,
        String confirmPassword
    ) {
        if (String.isBlank(firstName)) {
            throw new AuraHandledException('First name is required.');
        }

    if (String.isBlank(lastName)) {
      throw new AuraHandledException('Last name is required.');
    }

    if (String.isBlank(email)) {
      throw new AuraHandledException('Email is required.');
    }

    if (!email.contains('@')) {
      throw new AuraHandledException('Please enter a valid email address.');
    }

    if (String.isBlank(phone)) {
      throw new AuraHandledException('Phone number is required.');
    }

    if (String.isBlank(educationLevel)) {
      throw new AuraHandledException('Education level is required.');
    }

    if (yearsOfExperience == null || yearsOfExperience < 0) {
      throw new AuraHandledException(
        'Years of experience must be a positive number.'
      );
    }

    if (String.isBlank(password)) {
      throw new AuraHandledException('Password is required.');
    }

    if (password != confirmPassword) {
      throw new AuraHandledException('Password and confirmation do not match.');
    }

    if (password.length() < 8) {
      throw new AuraHandledException(
        'Password must contain at least 8 characters.'
      );
    }
  }

    /**
     * @description Returns the External Identity profile used to create candidate portal users.
     * @return External Identity profile.
     */
    private static Profile getExternalIdentityProfile() {
        if (!Schema.sObjectType.Profile.isAccessible()) {
            throw new AuraHandledException(
                'Profile access is not allowed for the current context. Please contact an administrator.'
            );
        }

        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :EXTERNAL_IDENTITY_PROFILE_NAME
            AND UserLicense.Name = :EXTERNAL_IDENTITY_LICENSE_NAME
            LIMIT 1
        ];

    if (profiles.isEmpty()) {
      throw new AuraHandledException(
        'External Identity profile is not configured. Please contact an administrator.'
      );
    }

    return profiles[0];
  }

    /**
     * @description Ensures no Salesforce user already exists with the same username/email.
     * @param normalizedEmail Lowercase trimmed email.
     */
    private static void ensureNoExistingUser(String normalizedEmail) {
        if (!Schema.sObjectType.User.isAccessible()) {
            throw new AuraHandledException(
                'User lookup is not allowed for the current context. Please contact an administrator.'
            );
        }

        List<User> existingUsers = [
            SELECT Id
            FROM User
            WHERE Username = :normalizedEmail
            LIMIT 1
        ];

    if (!existingUsers.isEmpty()) {
      throw new AuraHandledException(
        'An account already exists with this email.'
      );
    }
  }

    /**
     * @description Ensures no Candidate__c already exists with the same email or phone.
     * @param normalizedEmail Lowercase trimmed email.
     * @param normalizedPhone Trimmed phone number.
     */
    private static void ensureNoExistingCandidate(String normalizedEmail, String normalizedPhone) {
        if (!Schema.sObjectType.Candidate__c.isAccessible()) {
            throw new AuraHandledException(
                'Candidate lookup is not allowed for the current context. Please contact an administrator.'
            );
        }

        List<Candidate__c> existingCandidates = [
            SELECT Id
            FROM Candidate__c
            WHERE Email__c = :normalizedEmail OR Phone__c = :normalizedPhone
            LIMIT 1
        ];

    if (!existingCandidates.isEmpty()) {
      throw new AuraHandledException(
        'A candidate profile already exists with this email or phone number.'
      );
    }
  }

  /**
   * @description Builds a Salesforce user alias from candidate first and last name.
   * @param firstName Candidate first name.
   * @param lastName Candidate last name.
   * @return Alias with maximum 8 characters.
   */
  private static String buildAlias(String firstName, String lastName) {
    String rawAlias =
      (String.isBlank(firstName) ? '' : firstName.left(1)) +
      (String.isBlank(lastName) ? 'cand' : lastName);

    rawAlias = rawAlias.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();

    if (rawAlias.length() > 8) {
      rawAlias = rawAlias.left(8);
    }

    if (String.isBlank(rawAlias)) {
      rawAlias = 'cand';
    }

    return rawAlias;
  }

  /**
   * @description Builds a unique community nickname for the external candidate user.
   * @param firstName Candidate first name.
   * @param lastName Candidate last name.
   * @return Community nickname.
   */
  private static String buildCommunityNickname(
    String firstName,
    String lastName
  ) {
    String base =
      (String.isBlank(firstName) ? 'candidate' : firstName) +
      '.' +
      (String.isBlank(lastName) ? 'user' : lastName);

    base = base.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();

    String suffix = String.valueOf(DateTime.now().getTime()).right(6);
    String nickname = base + suffix;

    if (nickname.length() > 40) {
      nickname = nickname.left(34) + suffix;
    }

    return nickname;
  }

    /**
     * @description Queueable job that creates the Candidate__c profile after the portal user is created.
     */
    private class CandidateCreationJob implements Queueable {
        private Id userId;
        private String firstName;
        private String lastName;
        private String email;
        private String phone;
        private String educationLevel;
        private Decimal yearsOfExperience;

        /**
         * @description Creates a job carrying candidate profile data.
         * @param userId Created portal user id.
         * @param firstName Candidate first name.
         * @param lastName Candidate last name.
         * @param email Candidate email.
         * @param phone Candidate phone number.
         * @param educationLevel Candidate education level.
         * @param yearsOfExperience Candidate years of experience.
         */
        CandidateCreationJob(
            Id userId,
            String firstName,
            String lastName,
            String email,
            String phone,
            String educationLevel,
            Decimal yearsOfExperience
        ) {
            this.userId = userId;
            this.firstName = firstName;
            this.lastName = lastName;
            this.email = email;
            this.phone = phone;
            this.educationLevel = educationLevel;
            this.yearsOfExperience = yearsOfExperience;
        }

        /**
         * @description Creates the Candidate__c record linked to the newly created portal user.
         * @param context Queueable execution context.
         */
        public void execute(QueueableContext context) {
            if (!Schema.sObjectType.Candidate__c.isCreateable()) {
                throw new AuraHandledException(
                    'Candidate creation is not allowed for the current context. Please contact an administrator.'
                );
            }

            Candidate__c candidate = new Candidate__c(
                FirstName__c = firstName,
                LastName__c = lastName,
                Email__c = email,
                Phone__c = phone,
                Education_Level__c = educationLevel,
                Years_of_Experience__c = yearsOfExperience,
                Journey_Status__c = 'Active',
                User__c = userId
            );

            insert candidate;
        }
    }
}
