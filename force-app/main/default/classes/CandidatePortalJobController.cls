public without sharing class CandidatePortalProfileController {
  public class CandidateProfileDTO {
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
  }

  @AuraEnabled(cacheable=true)
  public static CandidateProfileDTO getCurrentCandidateProfile() {
    Id currentUserId = UserInfo.getUserId();

    List<Candidate__c> candidates = [
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
      WHERE User__c = :currentUserId
      LIMIT 1
    ];

    if (candidates.isEmpty()) {
      throw new AuraHandledException(
        'No candidate profile is linked to the current user. Current User Id: ' +
        currentUserId
      );
    }

    Candidate__c candidate = candidates[0];

    CandidateProfileDTO dto = new CandidateProfileDTO();
    dto.candidateId = candidate.Id;
    dto.firstName = candidate.FirstName__c;
    dto.lastName = candidate.LastName__c;
    dto.email = candidate.Email__c;
    dto.phone = candidate.Phone__c;
    dto.educationLevel = candidate.Education_Level__c;
    dto.yearsOfExperience = candidate.Years_of_Experience__c;

    return dto;
  }
}
