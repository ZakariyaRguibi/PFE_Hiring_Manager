/**
 * @description
 * Controller used by the Candidate Portal to expose the current candidate profile.
 */
public without sharing class CandidatePortalProfileController {
  /**
   * @description DTO exposed to the Candidate Profile LWC.
   */
  public class CandidateProfileDTO {
    @AuraEnabled
    public Boolean hasProfile;
    @AuraEnabled
    public Id candidateId;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String educationLevel;
    @AuraEnabled
    public Decimal yearsOfExperience;
    @AuraEnabled
    public String debugMessage;
  }

  /**
   * @description Returns the Candidate__c profile linked to the current portal user.
   * @return Current candidate profile DTO, or an empty DTO with debug context.
   */
  @AuraEnabled(cacheable=true)
  public static CandidateProfileDTO getCurrentCandidateProfile() {
    User currentUser = getCurrentUser();
    Candidate__c candidate = findCandidateForCurrentUser(currentUser);

    if (candidate == null) {
      return buildEmptyProfileDTO(currentUser);
    }

    return buildCandidateProfileDTO(candidate);
  }

  /**
   * @description Loads the current Salesforce user.
   * @return Current Salesforce user.
   */
  private static User getCurrentUser() {
    return [
      SELECT Id, Username, Email, Profile.Name, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  /**
   * @description Finds the Candidate__c record linked to the current portal user.
   * @param currentUser Current Salesforce user.
   * @return Candidate__c record linked to the current user, or null when none exists.
   */
  private static Candidate__c findCandidateForCurrentUser(User currentUser) {
    List<Candidate__c> candidatesByUser = [
      SELECT
        Id,
        FirstName__c,
        LastName__c,
        Email__c,
        Phone__c,
        Education_Level__c,
        Years_of_Experience__c,
        User__c
      FROM Candidate__c
      WHERE User__c = :currentUser.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!candidatesByUser.isEmpty()) {
      return candidatesByUser[0];
    }

    Set<String> possibleEmails = buildPossibleEmails(currentUser);

    if (possibleEmails.isEmpty()) {
      return null;
    }

    List<Candidate__c> candidatesByEmail = [
      SELECT
        Id,
        FirstName__c,
        LastName__c,
        Email__c,
        Phone__c,
        Education_Level__c,
        Years_of_Experience__c,
        User__c
      FROM Candidate__c
      WHERE Email__c IN :possibleEmails
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (candidatesByEmail.isEmpty()) {
      return null;
    }

    return candidatesByEmail[0];
  }

  /**
   * @description Builds possible email values for matching the current user.
   * @param currentUser Current Salesforce user.
   * @return Set of normalized email values.
   */
  private static Set<String> buildPossibleEmails(User currentUser) {
    Set<String> possibleEmails = new Set<String>();

    addNormalizedValue(possibleEmails, currentUser.Email);
    addNormalizedValue(possibleEmails, currentUser.Username);
    addNormalizedValue(possibleEmails, UserInfo.getUserEmail());

    return possibleEmails;
  }

  /**
   * @description Adds a normalized value to the set when not blank.
   * @param values Target set.
   * @param rawValue Raw value to normalize.
   */
  private static void addNormalizedValue(Set<String> values, String rawValue) {
    if (!String.isBlank(rawValue)) {
      values.add(rawValue.trim().toLowerCase());
    }
  }

  /**
   * @description Builds a portal-safe candidate profile DTO.
   * @param candidate Candidate__c record linked to the current portal user.
   * @return Candidate profile DTO.
   */
  private static CandidateProfileDTO buildCandidateProfileDTO(
    Candidate__c candidate
  ) {
    CandidateProfileDTO dto = new CandidateProfileDTO();
    dto.hasProfile = true;
    dto.candidateId = candidate.Id;
    dto.firstName = candidate.FirstName__c;
    dto.lastName = candidate.LastName__c;
    dto.email = candidate.Email__c;
    dto.phone = candidate.Phone__c;
    dto.educationLevel = candidate.Education_Level__c;
    dto.yearsOfExperience = candidate.Years_of_Experience__c;
    dto.debugMessage = null;

    return dto;
  }

  /**
   * @description Builds an empty profile DTO with debug context.
   * @param currentUser Current Salesforce user.
   * @return Empty profile DTO.
   */
  private static CandidateProfileDTO buildEmptyProfileDTO(User currentUser) {
    CandidateProfileDTO dto = new CandidateProfileDTO();
    dto.hasProfile = false;
    dto.debugMessage =
      'No candidate profile found. CurrentUserId=' +
      currentUser.Id +
      ', Username=' +
      currentUser.Username +
      ', Email=' +
      currentUser.Email +
      ', Profile=' +
      currentUser.Profile.Name +
      ', UserType=' +
      currentUser.UserType +
      ', UserInfoEmail=' +
      UserInfo.getUserEmail();

    return dto;
  }
}
