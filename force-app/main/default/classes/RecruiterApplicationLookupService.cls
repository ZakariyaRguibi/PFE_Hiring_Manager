/**
 * @description
 * Custom lookup service used by the recruiter manual Job Application creation LWC.
 * It avoids lightning-record-picker limitations on auto-number objects.
 */
public without sharing class RecruiterApplicationLookupService {
  public class LookupOptionDTO {
    @AuraEnabled
    public Id value { get; set; }

    @AuraEnabled
    public String label { get; set; }

    @AuraEnabled
    public String description { get; set; }

    @AuraEnabled
    public String extraInfo { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static List<LookupOptionDTO> searchCandidates(String searchTerm) {
    String cleanedTerm = cleanSearchTerm(searchTerm);

    if (String.isBlank(cleanedTerm)) {
      return new List<LookupOptionDTO>();
    }

    String searchPattern = '%' + cleanedTerm + '%';

    List<Candidate__c> candidates = [
      SELECT Id, FirstName__c, LastName__c, Email__c, Phone__c
      FROM Candidate__c
      WHERE FirstName__c LIKE :searchPattern OR LastName__c LIKE :searchPattern
      WITH SYSTEM_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 20
    ];

    List<LookupOptionDTO> results = new List<LookupOptionDTO>();

    for (Candidate__c candidate : candidates) {
      LookupOptionDTO option = new LookupOptionDTO();
      option.value = candidate.Id;
      option.label = buildCandidateFullName(candidate);
      option.description = candidate.Email__c;
      option.extraInfo = candidate.Phone__c;
      results.add(option);
    }

    return results;
  }

  @AuraEnabled(cacheable=true)
  public static List<LookupOptionDTO> searchOpenJobPositions(
    String searchTerm
  ) {
    String cleanedTerm = cleanSearchTerm(searchTerm);

    if (String.isBlank(cleanedTerm)) {
      return new List<LookupOptionDTO>();
    }

    String searchPattern = '%' + cleanedTerm + '%';

    List<Job_Position__c> jobs = [
      SELECT Id, Title__c, Status__c, Application_Deadline__c
      FROM Job_Position__c
      WHERE Title__c LIKE :searchPattern AND Status__c = 'Open'
      WITH SYSTEM_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 20
    ];

    List<LookupOptionDTO> results = new List<LookupOptionDTO>();

    for (Job_Position__c job : jobs) {
      LookupOptionDTO option = new LookupOptionDTO();
      option.value = job.Id;
      option.label = job.Title__c;
      option.description = 'Status: ' + job.Status__c;
      option.extraInfo =
        'Deadline: ' + String.valueOf(job.Application_Deadline__c);
      results.add(option);
    }

    return results;
  }

  private static String cleanSearchTerm(String searchTerm) {
    if (String.isBlank(searchTerm)) {
      return null;
    }

    return searchTerm.trim();
  }

  private static String buildCandidateFullName(Candidate__c candidate) {
    List<String> nameParts = new List<String>();

    if (!String.isBlank(candidate.FirstName__c)) {
      nameParts.add(candidate.FirstName__c);
    }

    if (!String.isBlank(candidate.LastName__c)) {
      nameParts.add(candidate.LastName__c);
    }

    String fullName = String.join(nameParts, ' ');

    if (!String.isBlank(fullName)) {
      return fullName;
    }

    if (!String.isBlank(candidate.Email__c)) {
      return candidate.Email__c;
    }

    return String.valueOf(candidate.Id);
  }
}
