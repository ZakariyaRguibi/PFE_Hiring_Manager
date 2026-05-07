public without sharing class CandidatePortalMyApplicationsController {
  public class ApplicationDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String jobTitle;
    @AuraEnabled
    public String applicationType;
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public String selectionStatus;
    @AuraEnabled
    public Datetime createdDate;
  }

  @AuraEnabled(cacheable=true)
  public static List<ApplicationDTO> getMyApplications() {
    Id currentUserId = UserInfo.getUserId();

    List<Candidate__c> candidates = [
      SELECT Id
      FROM Candidate__c
      WHERE User__c = :currentUserId
      LIMIT 1
    ];

    if (candidates.isEmpty()) {
      throw new AuraHandledException(
        'No candidate profile is linked to the current user.'
      );
    }

    List<Job_Application__c> applications = [
      SELECT
        Id,
        Name,
        CreatedDate,
        Application_Type__c,
        Stage__c,
        Selection_Status__c,
        Job_Position__c,
        Job_Position__r.Title__c
      FROM Job_Application__c
      WHERE Candidate__c = :candidates[0].Id
      ORDER BY CreatedDate DESC
    ];

    List<ApplicationDTO> results = new List<ApplicationDTO>();

    for (Job_Application__c application : applications) {
      ApplicationDTO dto = new ApplicationDTO();
      dto.id = application.Id;
      dto.name = application.Name;
      dto.applicationType = application.Application_Type__c;
      dto.stage = application.Stage__c;
      dto.selectionStatus = application.Selection_Status__c;
      dto.createdDate = application.CreatedDate;

      if (
        application.Job_Position__c != null &&
        application.Job_Position__r != null
      ) {
        dto.jobTitle = application.Job_Position__r.Title__c;
      } else {
        dto.jobTitle = 'Spontaneous Application';
      }

      results.add(dto);
    }

    return results;
  }
}
