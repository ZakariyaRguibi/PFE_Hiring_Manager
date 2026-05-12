/**
 * @description
 * Service used by internal recruiters to create Job_Application__c records
 * manually, for Referral or Spontaneous applications.
 */
public without sharing class JobApplicationSubmissionService {
  private static final String DEFAULT_APPLICATION_TYPE = 'Referral';
  private static final String APPLICATION_TYPE_REFERRAL = 'Referral';
  private static final String APPLICATION_TYPE_SPONTANEOUS = 'Spontaneous';
  private static final String DEFAULT_STAGE = 'New';
  private static final String PARSER_VERSION = 'PromptBuilder:CV_Parser:v1';

  public class ManualApplicationSubmissionRequest {
    @AuraEnabled
    public Id candidateId { get; set; }

    @AuraEnabled
    public Id jobPositionId { get; set; }

    @AuraEnabled
    public String applicationType { get; set; }

    @AuraEnabled
    public Id cvContentDocumentId { get; set; }

    @AuraEnabled
    public Id motivationLetterContentDocumentId { get; set; }

    @AuraEnabled
    public String extractedSkills { get; set; }

    @AuraEnabled
    public String extractedKeywords { get; set; }

    @AuraEnabled
    public String extractedEducation { get; set; }

    @AuraEnabled
    public Decimal extractedExperience { get; set; }

    @AuraEnabled
    public Boolean reusedExistingCvData { get; set; }
  }

  public class ManualApplicationSubmissionResult {
    @AuraEnabled
    public Id jobApplicationId { get; set; }

    @AuraEnabled
    public String applicationName { get; set; }

    @AuraEnabled
    public String message { get; set; }
  }

  public class ReusableParsingDataResult {
    @AuraEnabled
    public Boolean found { get; set; }

    @AuraEnabled
    public Id previousApplicationId { get; set; }

    @AuraEnabled
    public String extractedSkills { get; set; }

    @AuraEnabled
    public String extractedKeywords { get; set; }

    @AuraEnabled
    public String extractedEducation { get; set; }

    @AuraEnabled
    public Decimal extractedExperience { get; set; }

    @AuraEnabled
    public Datetime parsedAt { get; set; }

    @AuraEnabled
    public String parserVersion { get; set; }
  }

  @AuraEnabled
  public static ReusableParsingDataResult getReusableParsingData(
    Id candidateId,
    Id cvContentDocumentId
  ) {
    if (candidateId == null) {
      throw new AuraHandledException('Candidate is required.');
    }

    if (cvContentDocumentId == null) {
      throw new AuraHandledException('CV file is required.');
    }

    Job_Application__c previousApplication = findLatestApplicationUsingSameCv(
      candidateId,
      cvContentDocumentId
    );

    ReusableParsingDataResult result = new ReusableParsingDataResult();

    if (previousApplication == null) {
      result.found = false;
      return result;
    }

    result.found = true;
    result.previousApplicationId = previousApplication.Id;
    result.extractedSkills = previousApplication.Extracted_Skills__c;
    result.extractedKeywords = previousApplication.Extracted_Keywords__c;
    result.extractedEducation = previousApplication.Extracted_Education__c;
    result.extractedExperience = previousApplication.Extracted_Experience__c;
    result.parsedAt = previousApplication.Parsed_At__c;
    result.parserVersion = previousApplication.Parser_Version__c;

    return result;
  }

  @AuraEnabled
  public static ManualApplicationSubmissionResult submitManualApplication(
    ManualApplicationSubmissionRequest request
  ) {
    validateRequest(request);

    Candidate__c candidate = getCandidate(request.candidateId);
    String applicationType = getApplicationType(request);

    Job_Position__c jobPosition;

    if (applicationType == APPLICATION_TYPE_REFERRAL) {
      jobPosition = getOpenJobPosition(request.jobPositionId);
      preventDuplicateActiveApplication(candidate.Id, jobPosition.Id);
    }

    Job_Application__c application = new Job_Application__c();
    application.Candidate__c = candidate.Id;
    application.Application_Type__c = applicationType;
    application.Stage__c = DEFAULT_STAGE;

    if (jobPosition != null) {
      application.Job_Position__c = jobPosition.Id;
    }

    populateApplicationFromRequest(application, request, candidate.Id);

    Database.insert(application, AccessLevel.SYSTEM_MODE);

    linkApplicationFiles(application.Id, request);

    updateCandidateProfile(
      candidate.Id,
      application,
      request.reusedExistingCvData != true
    );

    return buildResult(application.Id);
  }

  private static void validateRequest(
    ManualApplicationSubmissionRequest request
  ) {
    if (request == null) {
      throw new AuraHandledException('Application request is required.');
    }

    if (request.candidateId == null) {
      throw new AuraHandledException('Candidate is required.');
    }

    String applicationType = getApplicationType(request);

    if (
      applicationType == APPLICATION_TYPE_REFERRAL &&
      request.jobPositionId == null
    ) {
      throw new AuraHandledException(
        'Job position is required for referral applications.'
      );
    }

    if (request.cvContentDocumentId == null) {
      throw new AuraHandledException('CV file is required.');
    }
  }

  private static Candidate__c getCandidate(Id candidateId) {
    List<Candidate__c> candidates = [
      SELECT Id, Skills__c, Education_Level__c, Years_of_Experience__c
      FROM Candidate__c
      WHERE Id = :candidateId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (candidates.isEmpty()) {
      throw new AuraHandledException('Selected candidate was not found.');
    }

    return candidates[0];
  }

  private static Job_Position__c getOpenJobPosition(Id jobPositionId) {
    List<Job_Position__c> jobs = [
      SELECT Id, Status__c, Application_Deadline__c
      FROM Job_Position__c
      WHERE Id = :jobPositionId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (jobs.isEmpty()) {
      throw new AuraHandledException('Selected job position was not found.');
    }

    Job_Position__c job = jobs[0];

    if (job.Status__c != 'Open') {
      throw new AuraHandledException('This job position is no longer open.');
    }

    if (
      job.Application_Deadline__c == null ||
      job.Application_Deadline__c < Date.today()
    ) {
      throw new AuraHandledException(
        'This job position is no longer accepting applications.'
      );
    }

    return job;
  }

  private static void preventDuplicateActiveApplication(
    Id candidateId,
    Id jobPositionId
  ) {
    Set<String> inactiveStages = new Set<String>{ 'Rejected', 'Withdrawn' };

    List<Job_Application__c> activeApplications = [
      SELECT Id
      FROM Job_Application__c
      WHERE
        Candidate__c = :candidateId
        AND Job_Position__c = :jobPositionId
        AND (Stage__c = NULL
        OR Stage__c NOT IN :inactiveStages)
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!activeApplications.isEmpty()) {
      throw new AuraHandledException(
        'This candidate already has an active application for this job position.'
      );
    }
  }

  private static String getApplicationType(
    ManualApplicationSubmissionRequest request
  ) {
    if (request == null || String.isBlank(request.applicationType)) {
      return DEFAULT_APPLICATION_TYPE;
    }

    if (
      request.applicationType != APPLICATION_TYPE_REFERRAL &&
      request.applicationType != APPLICATION_TYPE_SPONTANEOUS
    ) {
      throw new AuraHandledException(
        'Only Referral and Spontaneous applications can be created from this screen.'
      );
    }

    return request.applicationType;
  }

  private static void populateApplicationFromRequest(
    Job_Application__c application,
    ManualApplicationSubmissionRequest request,
    Id candidateId
  ) {
    application.CV_File_Id__c = String.valueOf(request.cvContentDocumentId);

    if (request.motivationLetterContentDocumentId != null) {
      application.Motivation_Letter__c = String.valueOf(
        request.motivationLetterContentDocumentId
      );
    }

    if (request.reusedExistingCvData == true) {
      populateFromExistingCv(application, request, candidateId);
      return;
    }

    populateFromNewCv(application, request, candidateId);
  }

  private static void populateFromNewCv(
    Job_Application__c application,
    ManualApplicationSubmissionRequest request,
    Id candidateId
  ) {
    Job_Application__c latestPreviousApplication = findLatestApplicationByCandidate(
      candidateId
    );

    if (latestPreviousApplication != null) {
      application.Previous_Application__c = latestPreviousApplication.Id;
    }

    application.Extracted_Skills__c = request.extractedSkills;
    application.Extracted_Keywords__c = request.extractedKeywords;
    application.Extracted_Education__c = request.extractedEducation;
    application.Extracted_Experience__c = request.extractedExperience;

    if (hasParsingData(request)) {
      application.Parsed_At__c = System.now();
      application.Parser_Version__c = PARSER_VERSION;
    }
  }

  private static void populateFromExistingCv(
    Job_Application__c application,
    ManualApplicationSubmissionRequest request,
    Id candidateId
  ) {
    Job_Application__c previousApplicationWithSameCv = findLatestApplicationUsingSameCv(
      candidateId,
      request.cvContentDocumentId
    );

    if (previousApplicationWithSameCv == null) {
      throw new AuraHandledException(
        'No previous parsed information was found for this CV. Please upload it as a new CV.'
      );
    }

    application.Previous_Application__c = previousApplicationWithSameCv.Id;
    application.Extracted_Skills__c = previousApplicationWithSameCv.Extracted_Skills__c;
    application.Extracted_Keywords__c = previousApplicationWithSameCv.Extracted_Keywords__c;
    application.Extracted_Education__c = previousApplicationWithSameCv.Extracted_Education__c;
    application.Extracted_Experience__c = previousApplicationWithSameCv.Extracted_Experience__c;
    application.Parsed_At__c = previousApplicationWithSameCv.Parsed_At__c;
    application.Parser_Version__c = previousApplicationWithSameCv.Parser_Version__c;
  }

  private static Job_Application__c findLatestApplicationByCandidate(
    Id candidateId
  ) {
    if (candidateId == null) {
      return null;
    }

    List<Job_Application__c> previousApplications = [
      SELECT Id
      FROM Job_Application__c
      WHERE Candidate__c = :candidateId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    return previousApplications.isEmpty() ? null : previousApplications[0];
  }

  private static Job_Application__c findLatestApplicationUsingSameCv(
    Id candidateId,
    Id cvContentDocumentId
  ) {
    if (candidateId == null || cvContentDocumentId == null) {
      return null;
    }

    String cvFileId = String.valueOf(cvContentDocumentId);

    List<Job_Application__c> previousApplications = [
      SELECT
        Id,
        CV_File_Id__c,
        Extracted_Skills__c,
        Extracted_Keywords__c,
        Extracted_Education__c,
        Extracted_Experience__c,
        Parsed_At__c,
        Parser_Version__c
      FROM Job_Application__c
      WHERE Candidate__c = :candidateId AND CV_File_Id__c = :cvFileId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    return previousApplications.isEmpty() ? null : previousApplications[0];
  }

  private static Boolean hasParsingData(
    ManualApplicationSubmissionRequest request
  ) {
    return !String.isBlank(request.extractedSkills) ||
      !String.isBlank(request.extractedKeywords) ||
      !String.isBlank(request.extractedEducation) ||
      request.extractedExperience != null;
  }

  private static void linkApplicationFiles(
    Id jobApplicationId,
    ManualApplicationSubmissionRequest request
  ) {
    linkFileToApplication(request.cvContentDocumentId, jobApplicationId);

    if (request.motivationLetterContentDocumentId != null) {
      linkFileToApplication(
        request.motivationLetterContentDocumentId,
        jobApplicationId
      );
    }
  }

  private static void linkFileToApplication(
    Id contentDocumentId,
    Id jobApplicationId
  ) {
    if (contentDocumentId == null || jobApplicationId == null) {
      return;
    }

    List<ContentDocumentLink> existingLinks = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE
        ContentDocumentId = :contentDocumentId
        AND LinkedEntityId = :jobApplicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (!existingLinks.isEmpty()) {
      return;
    }

    ContentDocumentLink linkToInsert = new ContentDocumentLink();
    linkToInsert.ContentDocumentId = contentDocumentId;
    linkToInsert.LinkedEntityId = jobApplicationId;
    linkToInsert.ShareType = 'V';
    linkToInsert.Visibility = 'AllUsers';

    Database.insert(linkToInsert, AccessLevel.SYSTEM_MODE);
  }

  private static void updateCandidateProfile(
    Id candidateId,
    Job_Application__c application,
    Boolean mergeCandidateSkills
  ) {
    Candidate__c candidateToUpdate = [
      SELECT
        Id,
        Skills__c,
        Education_Level__c,
        Years_of_Experience__c,
        Last_Application_Date__c
      FROM Candidate__c
      WHERE Id = :candidateId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (mergeCandidateSkills == true) {
      candidateToUpdate.Skills__c = mergeCommaSeparatedValues(
        candidateToUpdate.Skills__c,
        application.Extracted_Skills__c
      );
    }

    if (!String.isBlank(application.Extracted_Education__c)) {
      candidateToUpdate.Education_Level__c = application.Extracted_Education__c;
    }

    if (application.Extracted_Experience__c != null) {
      Decimal currentExperience = candidateToUpdate.Years_of_Experience__c;

      if (
        currentExperience == null ||
        application.Extracted_Experience__c > currentExperience
      ) {
        candidateToUpdate.Years_of_Experience__c = application.Extracted_Experience__c;
      }
    }

    candidateToUpdate.Last_Application_Date__c = Date.today();

    Database.update(candidateToUpdate, AccessLevel.SYSTEM_MODE);
  }

  private static ManualApplicationSubmissionResult buildResult(
    Id jobApplicationId
  ) {
    Job_Application__c application = [
      SELECT Id, Name
      FROM Job_Application__c
      WHERE Id = :jobApplicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    ManualApplicationSubmissionResult result = new ManualApplicationSubmissionResult();
    result.jobApplicationId = application.Id;
    result.applicationName = application.Name;
    result.message = 'Job application created successfully.';

    return result;
  }

  private static String mergeCommaSeparatedValues(
    String existingValues,
    String newValues
  ) {
    Map<String, String> normalizedToOriginal = new Map<String, String>();

    addValuesToMap(normalizedToOriginal, existingValues);
    addValuesToMap(normalizedToOriginal, newValues);

    List<String> mergedValues = new List<String>();

    for (String key : normalizedToOriginal.keySet()) {
      mergedValues.add(normalizedToOriginal.get(key));
    }

    mergedValues.sort();

    return String.join(mergedValues, ', ');
  }

  private static void addValuesToMap(
    Map<String, String> normalizedToOriginal,
    String values
  ) {
    if (String.isBlank(values)) {
      return;
    }

    for (String value : values.split(',')) {
      String cleaned = value == null ? null : value.trim();

      if (String.isBlank(cleaned)) {
        continue;
      }

      String normalized = cleaned.toLowerCase();

      if (!normalizedToOriginal.containsKey(normalized)) {
        normalizedToOriginal.put(normalized, cleaned);
      }
    }
  }
}
