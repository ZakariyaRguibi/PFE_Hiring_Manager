/**
 * @description
 * Service used by the TalentForce Candidate Portal to submit normal job
 * applications and spontaneous applications from Experience Cloud.
 *
 * Workflow:
 * - New uploaded CV:
 *   1. LWC uploads the CV as Salesforce File.
 *   2. LWC calls the CV parser.
 *   3. Candidate reviews extracted information.
 *   4. This service creates Job_Application__c.
 *   5. Extracted fields are saved on Job_Application__c.
 *   6. Parsed_At__c is set to now.
 *   7. Parser_Version__c is set to the current parser version.
 *   8. Previous_Application__c is populated with the latest previous application
 *      by the same candidate, when one exists.
 *   9. Extracted skills are merged into Candidate__c.Skills__c when needed.
 *
 * - Existing CV:
 *   1. LWC selects an existing Salesforce File.
 *   2. LWC does not call the CV parser again.
 *   3. This service reuses extracted fields from the latest previous application
 *      by the same candidate using the same CV.
 *
 * Security model:
 * - Candidate lookup is scoped to the current portal user through User__c,
 *   with email fallback for older candidate records.
 * - Previous applications are queried only for the resolved current candidate.
 * - Job application creation runs in system context because portal users should
 *   not need direct FLS on internal application fields populated by this service.
 */
public without sharing class CandidatePortalApplicationService {
  private static final String PARSER_VERSION = 'PromptBuilder:CV_Parser:v1';

  /**
   * @description Input payload sent by the candidate portal LWCs.
   */
  public class ApplicationSubmissionRequest {
    @AuraEnabled
    public Id jobPositionId { get; set; }

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

  /**
   * @description Result returned after successful application submission.
   */
  public class ApplicationSubmissionResult {
    @AuraEnabled
    public Id jobApplicationId { get; set; }

    @AuraEnabled
    public String applicationName { get; set; }

    @AuraEnabled
    public String message { get; set; }
  }

  /**
   * @description Reusable parsing data found from the latest previous application using the same CV.
   */
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

  /**
   * @description Returns reusable CV parsing information for the current candidate and selected CV.
   * @param cvContentDocumentId Salesforce Files ContentDocumentId of the selected CV.
   * @return ReusableParsingDataResult containing extracted fields and parser metadata.
   */
  @AuraEnabled
  public static ReusableParsingDataResult getReusableParsingData(
    Id cvContentDocumentId
  ) {
    if (cvContentDocumentId == null) {
      throw new AuraHandledException('CV file is required.');
    }

    Candidate__c currentCandidate = getCurrentCandidate();

    Job_Application__c previousApplication = findLatestApplicationUsingSameCv(
      currentCandidate.Id,
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

  /**
   * @description Submits a normal portal application linked to a Job_Position__c.
   * @param request Application submission payload.
   * @return ApplicationSubmissionResult containing the created application reference.
   */
  @AuraEnabled
  public static ApplicationSubmissionResult submitApplication(
    ApplicationSubmissionRequest request
  ) {
    validateJobApplicationRequest(request);

    Candidate__c currentCandidate = getCurrentCandidate();
    Job_Position__c jobPosition = getOpenJobPosition(request.jobPositionId);

    preventDuplicateActiveApplication(currentCandidate.Id, jobPosition.Id);

    Job_Application__c application = new Job_Application__c();
    application.Candidate__c = currentCandidate.Id;
    application.Job_Position__c = jobPosition.Id;
    application.Application_Type__c = 'Portal';
    application.Stage__c = 'New';

    populateApplicationFromRequest(application, request, currentCandidate.Id);

    Database.insert(application, AccessLevel.SYSTEM_MODE);

    linkApplicationFiles(application.Id, request);

    updateCandidateProfile(
      currentCandidate.Id,
      application,
      shouldMergeCandidateSkills(request)
    );

    return buildResult(application.Id, 'Application submitted successfully.');
  }

  /**
   * @description Submits a spontaneous application without Job_Position__c.
   * @param request Application submission payload.
   * @return ApplicationSubmissionResult containing the created application reference.
   */
  @AuraEnabled
  public static ApplicationSubmissionResult submitSpontaneousApplication(
    ApplicationSubmissionRequest request
  ) {
    validateSpontaneousApplicationRequest(request);

    Candidate__c currentCandidate = getCurrentCandidate();

    Job_Application__c application = new Job_Application__c();
    application.Candidate__c = currentCandidate.Id;
    application.Application_Type__c = 'Spontaneous';
    application.Stage__c = 'New';

    populateApplicationFromRequest(application, request, currentCandidate.Id);

    Database.insert(application, AccessLevel.SYSTEM_MODE);

    linkApplicationFiles(application.Id, request);

    updateCandidateProfile(
      currentCandidate.Id,
      application,
      shouldMergeCandidateSkills(request)
    );

    return buildResult(
      application.Id,
      'Spontaneous application submitted successfully.'
    );
  }

  /**
   * @description Validates a normal job application request.
   * @param request Application submission payload.
   */
  private static void validateJobApplicationRequest(
    ApplicationSubmissionRequest request
  ) {
    validateBaseRequest(request);

    if (request.jobPositionId == null) {
      throw new AuraHandledException('Job position is required.');
    }
  }

  /**
   * @description Validates a spontaneous application request.
   * @param request Application submission payload.
   */
  private static void validateSpontaneousApplicationRequest(
    ApplicationSubmissionRequest request
  ) {
    validateBaseRequest(request);
  }

  /**
   * @description Validates fields common to normal and spontaneous applications.
   * @param request Application submission payload.
   */
  private static void validateBaseRequest(
    ApplicationSubmissionRequest request
  ) {
    if (request == null) {
      throw new AuraHandledException('Application request is required.');
    }

    if (request.cvContentDocumentId == null) {
      throw new AuraHandledException('CV file is required.');
    }
  }

  /**
   * @description Gets the Candidate__c profile linked to the current portal user.
   * @return Candidate__c current candidate profile.
   */
  private static Candidate__c getCurrentCandidate() {
    User currentUser = getCurrentUser();

    List<Candidate__c> candidatesByUser = [
      SELECT Id, FirstName__c, LastName__c, Email__c, User__c
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
      throwNoCandidateProfileError();
    }

    List<Candidate__c> candidatesByEmail = [
      SELECT Id, FirstName__c, LastName__c, Email__c, User__c
      FROM Candidate__c
      WHERE Email__c IN :possibleEmails
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (candidatesByEmail.isEmpty()) {
      throwNoCandidateProfileError();
    }

    return candidatesByEmail[0];
  }

  /**
   * @description Loads the current Salesforce user.
   * @return Current Salesforce user.
   */
  private static User getCurrentUser() {
    return [
      SELECT Id, Username, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
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
   * @param rawValue Raw value.
   */
  private static void addNormalizedValue(Set<String> values, String rawValue) {
    if (!String.isBlank(rawValue)) {
      values.add(rawValue.trim().toLowerCase());
    }
  }

  /**
   * @description Throws the standard no-candidate error.
   */
  private static void throwNoCandidateProfileError() {
    throw new AuraHandledException(
      'No candidate profile is linked to the current user.'
    );
  }

  /**
   * @description Gets and validates the selected job position.
   * @param jobPositionId Job_Position__c Id.
   * @return Selected Job_Position__c record.
   */
  private static Job_Position__c getOpenJobPosition(Id jobPositionId) {
    if (jobPositionId == null) {
      throw new AuraHandledException('Job position is required.');
    }

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

    validateJobStatus(job);
    validateJobDeadline(job);

    return job;
  }

  /**
   * @description Validates that the selected job is open for portal applications.
   * @param job Selected Job_Position__c record.
   */
  private static void validateJobStatus(Job_Position__c job) {
    if (job.Status__c != 'Open') {
      throw new AuraHandledException('This job position is no longer open.');
    }
  }

  /**
   * @description Validates that the selected job has a valid application deadline.
   * @param job Selected Job_Position__c record.
   */
  private static void validateJobDeadline(Job_Position__c job) {
    if (
      job.Application_Deadline__c == null ||
      job.Application_Deadline__c < Date.today()
    ) {
      throw new AuraHandledException(
        'This job position is no longer accepting applications.'
      );
    }
  }

  /**
   * @description Prevents duplicate active applications for the same candidate and job.
   * A candidate can apply again only when all previous applications for the same
   * job are Rejected or Withdrawn.
   * @param candidateId Candidate__c Id.
   * @param jobPositionId Job_Position__c Id.
   */
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
        'You already have an active application for this job position.'
      );
    }
  }

  /**
   * @description Populates a new Job_Application__c from the portal request.
   * @param application Application record being created.
   * @param request Application submission payload.
   * @param candidateId Candidate__c Id.
   */
  private static void populateApplicationFromRequest(
    Job_Application__c application,
    ApplicationSubmissionRequest request,
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

  /**
   * @description Populates application data when the candidate uploads a new CV.
   * @param application Application record being created.
   * @param request Application submission payload.
   * @param candidateId Candidate__c Id.
   */
  private static void populateFromNewCv(
    Job_Application__c application,
    ApplicationSubmissionRequest request,
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

  /**
   * @description Populates application data when the candidate reuses an existing CV.
   * @param application Application record being created.
   * @param request Application submission payload.
   * @param candidateId Candidate__c Id.
   */
  private static void populateFromExistingCv(
    Job_Application__c application,
    ApplicationSubmissionRequest request,
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

  /**
   * @description Finds the latest previous application by the same candidate.
   * @param candidateId Candidate__c Id.
   * @return Latest Job_Application__c for the candidate, or null.
   */
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

  /**
   * @description Finds the latest previous application by the same candidate using the same CV.
   * @param candidateId Candidate__c Id.
   * @param cvContentDocumentId ContentDocumentId of the selected CV.
   * @return Latest Job_Application__c using the same CV, or null.
   */
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

  /**
   * @description Checks whether the request contains parsed CV data.
   * @param request Application submission payload.
   * @return true when at least one parsing field is present.
   */
  private static Boolean hasParsingData(ApplicationSubmissionRequest request) {
    return !String.isBlank(request.extractedSkills) ||
      !String.isBlank(request.extractedKeywords) ||
      !String.isBlank(request.extractedEducation) ||
      request.extractedExperience != null;
  }

  /**
   * @description Links selected Salesforce Files to the created application.
   * @param jobApplicationId Created Job_Application__c Id.
   * @param request Application submission payload.
   */
  private static void linkApplicationFiles(
    Id jobApplicationId,
    ApplicationSubmissionRequest request
  ) {
    linkFileToApplication(request.cvContentDocumentId, jobApplicationId);

    if (request.motivationLetterContentDocumentId != null) {
      linkFileToApplication(
        request.motivationLetterContentDocumentId,
        jobApplicationId
      );
    }
  }

  /**
   * @description Creates a ContentDocumentLink between a Salesforce File and the application.
   * @param contentDocumentId Salesforce Files ContentDocumentId.
   * @param jobApplicationId Job_Application__c Id.
   */
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

  /**
   * @description Decides whether parsed skills should be merged into Candidate__c.Skills__c.
   * @param request Application submission payload.
   * @return true when candidate skills should be enriched.
   */
  private static Boolean shouldMergeCandidateSkills(
    ApplicationSubmissionRequest request
  ) {
    return request != null && request.reusedExistingCvData != true;
  }

  /**
   * @description Updates the candidate enriched profile fields after submission.
   * @param candidateId Candidate__c Id.
   * @param application Created application record containing extracted data.
   * @param mergeCandidateSkills true when Candidate__c.Skills__c should be updated.
   */
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

    Boolean hasCandidateUpdate = false;

    if (mergeCandidateSkills == true) {
      candidateToUpdate.Skills__c = mergeCommaSeparatedValues(
        candidateToUpdate.Skills__c,
        application.Extracted_Skills__c
      );
      hasCandidateUpdate = true;
    }

    if (!String.isBlank(application.Extracted_Education__c)) {
      candidateToUpdate.Education_Level__c = application.Extracted_Education__c;
      hasCandidateUpdate = true;
    }

    if (application.Extracted_Experience__c != null) {
      Decimal currentExperience = candidateToUpdate.Years_of_Experience__c;

      if (
        currentExperience == null ||
        application.Extracted_Experience__c > currentExperience
      ) {
        candidateToUpdate.Years_of_Experience__c = application.Extracted_Experience__c;
        hasCandidateUpdate = true;
      }
    }

    candidateToUpdate.Last_Application_Date__c = Date.today();
    hasCandidateUpdate = true;

    if (hasCandidateUpdate) {
      Database.update(candidateToUpdate, AccessLevel.SYSTEM_MODE);
    }
  }

  /**
   * @description Builds the response returned to the portal after insert.
   * @param jobApplicationId Created application Id.
   * @param message User-facing success message.
   * @return ApplicationSubmissionResult with application Id, name, and message.
   */
  private static ApplicationSubmissionResult buildResult(
    Id jobApplicationId,
    String message
  ) {
    Job_Application__c insertedApplication = [
      SELECT Id, Name
      FROM Job_Application__c
      WHERE Id = :jobApplicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    ApplicationSubmissionResult result = new ApplicationSubmissionResult();
    result.jobApplicationId = insertedApplication.Id;
    result.applicationName = insertedApplication.Name;
    result.message = message;

    return result;
  }

  /**
   * @description Merges comma-separated strings while removing duplicates case-insensitively.
   * @param existingValues Existing comma-separated values.
   * @param newValues New comma-separated values.
   * @return Merged comma-separated values.
   */
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

  /**
   * @description Adds cleaned comma-separated values to a normalized map.
   * @param normalizedToOriginal Map from lowercase normalized value to original value.
   * @param values Comma-separated values.
   */
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
