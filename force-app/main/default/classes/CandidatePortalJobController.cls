/**
 * @description
 * Controller used by the TalentForce Candidate Portal to expose open job positions.
 *
 * This controller supports the public job browser and returns only the fields
 * required by the portal UI through a DTO.
 *
 * Security note:
 * - Open jobs are intentionally exposed on the candidate portal.
 * - Object read access is validated before querying Job_Position__c.
 * - The query only returns public portal fields through a DTO.
 */
public without sharing class CandidatePortalJobController {
  /**
   * @description Returns open job positions visible in the candidate portal.
   * @return List of open job position DTOs ordered from newest to oldest.
   */
  @AuraEnabled(cacheable=true)
  public static List<JobPositionDTO> getOpenJobs() {
    if (!Schema.sObjectType.Job_Position__c.isAccessible()) {
      throw new AuraHandledException(
        'You do not have access to job positions.'
      );
    }

    List<Job_Position__c> openJobs = [
      SELECT Id, Title__c, Application_Deadline__c, Portal_Description__c
      FROM Job_Position__c
      WHERE Status__c = 'Open'
      ORDER BY CreatedDate DESC
    ];

    List<JobPositionDTO> jobs = new List<JobPositionDTO>();

    for (Job_Position__c job : openJobs) {
      jobs.add(new JobPositionDTO(job));
    }

    return jobs;
  }

  /**
   * @description DTO exposed to the candidate portal job list LWC.
   */
  public class JobPositionDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public Date applicationDeadline;
    @AuraEnabled
    public String portalDescription;

    /**
     * @description Builds a job position DTO from a Job_Position__c record.
     * @param job Source Job_Position__c record.
     */
    public JobPositionDTO(Job_Position__c job) {
      this.id = job.Id;
      this.title = job.Title__c;
      this.applicationDeadline = job.Application_Deadline__c;
      this.portalDescription = job.Portal_Description__c;
    }
  }
}
