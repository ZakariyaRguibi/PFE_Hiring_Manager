/**
 * @description Controller used by the candidate portal to retrieve the applications
 * linked to the currently logged-in candidate user.
 *
 * The class runs without sharing because candidate portal users may not always have
 * direct sharing access to their Candidate__c record. Access is still restricted by
 * filtering records through Candidate__c.User__c = UserInfo.getUserId().
 */
public without sharing class CandidatePortalMyApplicationsController {
  /**
   * @description Data transfer object returned to the LWC to display a candidate application.
   */
  public class ApplicationDTO {
    /** @description Job_Application__c record Id. */
    @AuraEnabled
    public Id id;

    /** @description Job_Application__c record name. */
    @AuraEnabled
    public String name;

    /** @description Related job title, or Spontaneous Application when no job position is linked. */
    @AuraEnabled
    public String jobTitle;

    /** @description Application type, for example Portal or Spontaneous. */
    @AuraEnabled
    public String applicationType;

    /** @description Current application stage. */
    @AuraEnabled
    public String stage;

    /** @description Current selection status of the application. */
    @AuraEnabled
    public String selectionStatus;

    /** @description Creation date of the application. */
    @AuraEnabled
    public Datetime createdDate;
  }

  /**
   * @description Returns the list of applications linked to the candidate profile
   * associated with the current Salesforce user.
   *
   * @return List of application DTOs ordered by creation date descending.
   * @throws AuraHandledException when no candidate profile is linked to the current user
   * or when the user does not have read access to the required objects.
   */
  @AuraEnabled(cacheable=true)
  public static List<ApplicationDTO> getMyApplications() {
    validateReadAccess();

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

  /**
   * @description Verifies that the current user has read access to the objects
   * required by the My Applications portal page before executing SOQL queries.
   *
   * @throws AuraHandledException when the current user does not have the required read access.
   */
  private static void validateReadAccess() {
    if (
      !Schema.sObjectType.Candidate__c.isAccessible() ||
      !Schema.sObjectType.Job_Application__c.isAccessible() ||
      !Schema.sObjectType.Job_Position__c.isAccessible()
    ) {
      throw new AuraHandledException(
        'You do not have permission to view application records.'
      );
    }
  }
}
