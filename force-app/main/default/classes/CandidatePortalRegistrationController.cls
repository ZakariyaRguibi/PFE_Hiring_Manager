/**
 * @description Controller used by the TalentForce Candidate Portal self-registration form.
 * It creates an External Identity user account, assigns the required candidate permission sets,
 * sets the password chosen by the candidate, asynchronously creates the related Candidate__c profile,
 * and shares that candidate profile with the newly created portal user.
 *
 * The class runs without sharing intentionally because guest users must be able to start
 * the registration process before they own any Salesforce records.
 */
public without sharing class CandidatePortalRegistrationController {
  private static final String EXTERNAL_IDENTITY_PROFILE_NAME = 'External Identity User';
  private static final String EXTERNAL_IDENTITY_LICENSE_NAME = 'External Identity';
  private static final String CANDIDATE_PERMISSION_SET_NAME = 'TF_Candidate';

  private static final String PROMPT_TEMPLATE_PERMISSION_SET_LABEL = 'Prompt Template User';
  private static final Set<String> PROMPT_TEMPLATE_PERMISSION_SET_NAMES = new Set<String>{
    'Prompt_Template_User',
    'PromptTemplateUser'
  };

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
    try {
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

      String trimmedFirstName = firstName.trim();
      String trimmedLastName = lastName.trim();
      String normalizedEmail = email.trim().toLowerCase();
      String normalizedPhone = phone != null ? phone.trim() : null;
      String trimmedEducationLevel = educationLevel.trim();

      ensureNoExistingUser(normalizedEmail);
      ensureNoExistingCandidate(normalizedEmail, normalizedPhone);

      Profile externalIdentityProfile = getExternalIdentityProfile();

      User newUser = buildExternalIdentityUser(
        trimmedFirstName,
        trimmedLastName,
        normalizedEmail,
        externalIdentityProfile.Id
      );

      Database.insert(newUser, AccessLevel.SYSTEM_MODE);

      assignCandidatePermissionSets(newUser.Id);
      System.setPassword(newUser.Id, password);

      System.enqueueJob(
        new CandidateCreationJob(
          newUser.Id,
          trimmedFirstName,
          trimmedLastName,
          normalizedEmail,
          normalizedPhone,
          trimmedEducationLevel,
          yearsOfExperience
        )
      );

      RegistrationResult result = new RegistrationResult();
      result.success = true;
      result.message = 'Account created successfully. You can now log in.';
      result.username = normalizedEmail;
      result.userId = newUser.Id;

      return result;
    } catch (AuraHandledException exceptionToSurface) {
      throw exceptionToSurface;
    } catch (DmlException dmlException) {
      throw new AuraHandledException(buildDmlErrorMessage(dmlException));
    } catch (Exception unexpectedException) {
      throw new AuraHandledException(
        'Unable to create your account. Please contact an administrator.'
      );
    }
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
   * @param confirmPassword Password confirmation.
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

    if (!isValidEmail(email)) {
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
   * @description Checks whether the provided email has a basic valid format.
   * @param email Email to validate.
   * @return True when the email has a valid basic format.
   */
  private static Boolean isValidEmail(String email) {
    Pattern emailPattern = Pattern.compile(
      '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'
    );

    return emailPattern.matcher(email.trim()).matches();
  }

  /**
   * @description Returns the External Identity profile used to create candidate portal users.
   * @return External Identity profile.
   */
  private static Profile getExternalIdentityProfile() {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE
        Name = :EXTERNAL_IDENTITY_PROFILE_NAME
        AND UserLicense.Name = :EXTERNAL_IDENTITY_LICENSE_NAME
      WITH SYSTEM_MODE
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
   * @description Ensures no Salesforce user already exists with the same username.
   * @param normalizedEmail Lowercase trimmed email.
   */
  private static void ensureNoExistingUser(String normalizedEmail) {
    List<User> existingUsers = [
      SELECT Id
      FROM User
      WHERE Username = :normalizedEmail
      WITH SYSTEM_MODE
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
  private static void ensureNoExistingCandidate(
    String normalizedEmail,
    String normalizedPhone
  ) {
    List<Candidate__c> existingCandidates = [
      SELECT Id
      FROM Candidate__c
      WHERE Email__c = :normalizedEmail OR Phone__c = :normalizedPhone
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!existingCandidates.isEmpty()) {
      throw new AuraHandledException(
        'A candidate profile already exists with this email or phone number.'
      );
    }
  }

  /**
   * @description Builds the external identity user record.
   * @param firstName Candidate first name.
   * @param lastName Candidate last name.
   * @param normalizedEmail Candidate normalized email.
   * @param profileId External Identity profile id.
   * @return User record ready to insert.
   */
  private static User buildExternalIdentityUser(
    String firstName,
    String lastName,
    String normalizedEmail,
    Id profileId
  ) {
    return new User(
      FirstName = firstName,
      LastName = lastName,
      Email = normalizedEmail,
      Username = normalizedEmail,
      Alias = buildAlias(firstName, lastName),
      CommunityNickname = buildCommunityNickname(firstName, lastName),
      TimeZoneSidKey = 'Africa/Casablanca',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = profileId,
      IsActive = true
    );
  }

  /**
   * @description Assigns all required permission sets to the newly created candidate portal user.
   * @param userId Created candidate portal user id.
   */
  private static void assignCandidatePermissionSets(Id userId) {
    List<PermissionSet> candidatePermissionSets = [
      SELECT Id, Name, Label
      FROM PermissionSet
      WHERE Name = :CANDIDATE_PERMISSION_SET_NAME
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (candidatePermissionSets.isEmpty()) {
      throw new AuraHandledException(
        'TF_Candidate permission set is not configured. Please contact an administrator.'
      );
    }

    List<PermissionSet> permissionSetsToAssign = new List<PermissionSet>();
    permissionSetsToAssign.add(candidatePermissionSets[0]);

    List<PermissionSet> promptTemplatePermissionSets = [
      SELECT Id, Name, Label
      FROM PermissionSet
      WHERE
        Name IN :PROMPT_TEMPLATE_PERMISSION_SET_NAMES
        OR Label = :PROMPT_TEMPLATE_PERMISSION_SET_LABEL
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!promptTemplatePermissionSets.isEmpty()) {
      permissionSetsToAssign.add(promptTemplatePermissionSets[0]);
    }

    insertMissingPermissionSetAssignments(userId, permissionSetsToAssign);
  }

  /**
   * @description Inserts missing permission set assignments for a user.
   * @param userId User receiving the permission sets.
   * @param permissionSets Permission sets to assign.
   */
  private static void insertMissingPermissionSetAssignments(
    Id userId,
    List<PermissionSet> permissionSets
  ) {
    Set<Id> permissionSetIds = new Set<Id>();

    for (PermissionSet permissionSetRecord : permissionSets) {
      permissionSetIds.add(permissionSetRecord.Id);
    }

    if (permissionSetIds.isEmpty()) {
      return;
    }

    List<PermissionSetAssignment> existingAssignments = [
      SELECT Id, PermissionSetId
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId AND PermissionSetId IN :permissionSetIds
      WITH SYSTEM_MODE
    ];

    Set<Id> alreadyAssignedPermissionSetIds = new Set<Id>();

    for (PermissionSetAssignment existingAssignment : existingAssignments) {
      alreadyAssignedPermissionSetIds.add(existingAssignment.PermissionSetId);
    }

    List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>();

    for (Id permissionSetId : permissionSetIds) {
      if (!alreadyAssignedPermissionSetIds.contains(permissionSetId)) {
        assignmentsToInsert.add(
          new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permissionSetId
          )
        );
      }
    }

    if (!assignmentsToInsert.isEmpty()) {
      Database.insert(assignmentsToInsert, AccessLevel.SYSTEM_MODE);
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
   * @description Builds a user-friendly DML error message.
   * @param dmlException DML exception thrown during provisioning.
   * @return Safe error message for the portal user.
   */
  private static String buildDmlErrorMessage(DmlException dmlException) {
    if (dmlException.getNumDml() > 0) {
      String statusCode = String.valueOf(dmlException.getDmlStatusCode(0));

      if (statusCode == 'DUPLICATE_USERNAME') {
        return 'An account already exists with this email.';
      }

      if (statusCode == 'DUPLICATE_VALUE') {
        return 'A record already exists with the same information.';
      }

      if (statusCode == 'FIELD_INTEGRITY_EXCEPTION') {
        return 'Some registration information is invalid. Please contact an administrator.';
      }
    }

    return 'Unable to create your account. Please contact an administrator.';
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

      Database.insert(candidate, AccessLevel.SYSTEM_MODE);
    }
  }
}
