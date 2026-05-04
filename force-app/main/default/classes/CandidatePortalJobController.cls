/**
 * @description Controller used by the TalentForce Candidate Portal to expose public job positions.
 * It returns only job positions that are open and whose application deadline has not expired.
 */
public with sharing class CandidatePortalJobController {
    /**
     * @description Data transfer object representing a public job position displayed on the candidate portal.
     */
    public class JobPositionDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String title;
        @AuraEnabled public Date applicationDeadline;
        @AuraEnabled public String portalDescription;
    }

    /**
     * @description Returns open and non-expired job positions visible to candidate portal users.
     * @return List of public job position DTOs.
     */
    @AuraEnabled(cacheable=true)
    public static List<JobPositionDTO> getOpenJobs() {
        List<Job_Position__c> jobPositions = [
            SELECT Id,
                   Title__c,
                   Application_Deadline__c,
                   Portal_Description__c
            FROM Job_Position__c
            WHERE Status__c = 'Open'
            AND Application_Deadline__c >= TODAY
            WITH USER_MODE
            ORDER BY Application_Deadline__c ASC
        ];

        List<JobPositionDTO> jobs = new List<JobPositionDTO>();

        for (Job_Position__c jobPosition : jobPositions) {
            JobPositionDTO dto = new JobPositionDTO();
            dto.recordId = jobPosition.Id;
            dto.title = jobPosition.Title__c;
            dto.applicationDeadline = jobPosition.Application_Deadline__c;
            dto.portalDescription = jobPosition.Portal_Description__c;
            jobs.add(dto);
        }

        return jobs;
    }
}
