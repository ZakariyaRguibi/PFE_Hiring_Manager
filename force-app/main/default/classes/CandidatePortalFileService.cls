/**
 * @description
 * Service used by the Candidate Portal to upload and retrieve candidate files
 * using standard Salesforce Files.
 *
 * Files are linked to the Candidate__c record through FirstPublishLocationId.
 * The portal then reuses ContentDocumentId values during job application and
 * spontaneous application submission.
 *
 * Only PDF files are accepted because the CV analysis Prompt Template does not
 * support DOC or DOCX files.
 */
public without sharing class CandidatePortalFileService {
  private static final String SUPPORTED_FILE_MESSAGE = 'Only PDF files are supported. Please convert your document to PDF before uploading.';

  /**
   * @description Result returned after uploading a candidate file.
   */
  public class UploadedFileResult {
    @AuraEnabled
    public String fileName { get; set; }
    @AuraEnabled
    public Id contentVersionId { get; set; }
    @AuraEnabled
    public Id contentDocumentId { get; set; }
    @AuraEnabled
    public Id linkedCandidateId { get; set; }
  }

  /**
   * @description DTO representing a candidate file available for reuse.
   */
  public class CandidateFileDTO {
    @AuraEnabled
    public Id contentDocumentId { get; set; }
    @AuraEnabled
    public Id contentVersionId { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String fileName { get; set; }
    @AuraEnabled
    public String fileType { get; set; }
    @AuraEnabled
    public Integer contentSize { get; set; }
    @AuraEnabled
    public Datetime createdDate { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public String previewUrl { get; set; }
    @AuraEnabled
    public String downloadUrl { get; set; }
  }

  /**
   * @description
   * Returns reusable candidate PDF files linked to the current candidate.
   *
   * This method is not cacheable because it may create missing
   * ContentDistribution records to generate browser-safe preview/download URLs.
   *
   * @return List of reusable candidate files.
   */
  @AuraEnabled(cacheable=false)
  public static List<CandidateFileDTO> getCandidateFiles() {
    Candidate__c currentCandidate = findCurrentCandidate();

    if (currentCandidate == null) {
      return new List<CandidateFileDTO>();
    }

    return getFilesForCandidate(currentCandidate.Id);
  }

  /**
   * @description
   * Uploads a temporary PDF file as Salesforce File and links it to the current Candidate__c.
   *
   * @param fileName Original file name.
   * @param base64Data Base64 encoded file content.
   * @return Uploaded file metadata including ContentDocumentId.
   */
  @AuraEnabled
  public static UploadedFileResult uploadTemporaryFile(
    String fileName,
    String base64Data
  ) {
    validateUploadInput(fileName, base64Data);

    Candidate__c currentCandidate = findCurrentCandidate();

    if (currentCandidate == null) {
      throw new AuraHandledException(
        'No candidate profile is linked to the current user.'
      );
    }

    Blob fileBody = decodeFileBody(base64Data);

    ContentVersion contentVersion = new ContentVersion(
      Title = cleanTitle(fileName),
      PathOnClient = fileName,
      VersionData = fileBody,
      FirstPublishLocationId = currentCandidate.Id
    );

    Database.insert(contentVersion, AccessLevel.SYSTEM_MODE);

    ContentVersion insertedVersion = [
      SELECT Id, ContentDocumentId, Title
      FROM ContentVersion
      WHERE Id = :contentVersion.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    UploadedFileResult result = new UploadedFileResult();
    result.fileName = fileName;
    result.contentVersionId = insertedVersion.Id;
    result.contentDocumentId = insertedVersion.ContentDocumentId;
    result.linkedCandidateId = currentCandidate.Id;

    return result;
  }

  /**
   * @description Validates upload input.
   * @param fileName Original file name.
   * @param base64Data Base64 encoded file content.
   */
  private static void validateUploadInput(String fileName, String base64Data) {
    if (String.isBlank(fileName)) {
      throw new AuraHandledException('File name is required.');
    }

    if (String.isBlank(base64Data)) {
      throw new AuraHandledException('File content is required.');
    }

    if (!isSupportedDocument(fileName)) {
      throw new AuraHandledException(SUPPORTED_FILE_MESSAGE);
    }
  }

  /**
   * @description Decodes Base64 file body.
   * @param base64Data Base64 encoded file content.
   * @return Decoded file body.
   */
  private static Blob decodeFileBody(String base64Data) {
    try {
      return EncodingUtil.base64Decode(base64Data);
    } catch (Exception decodeException) {
      throw new AuraHandledException('Invalid file content.');
    }
  }

  /**
   * @description Finds the Candidate__c profile linked to the current portal user.
   * @return Current Candidate__c record, or null when not found.
   */
  private static Candidate__c findCurrentCandidate() {
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
      return null;
    }

    List<Candidate__c> candidatesByEmail = [
      SELECT Id, FirstName__c, LastName__c, Email__c, User__c
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
   * @description Loads PDF Salesforce Files linked to the candidate.
   * @param candidateId Candidate record id.
   * @return File DTO list.
   */
  private static List<CandidateFileDTO> getFilesForCandidate(Id candidateId) {
    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :candidateId
      WITH SYSTEM_MODE
    ];

    if (links.isEmpty()) {
      return new List<CandidateFileDTO>();
    }

    Set<Id> documentIds = extractDocumentIds(links);

    List<ContentVersion> versions = [
      SELECT
        Id,
        ContentDocumentId,
        Title,
        PathOnClient,
        FileType,
        ContentSize,
        CreatedDate
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];

    return buildFileDTOs(versions);
  }

  /**
   * @description Extracts ContentDocument Ids from document links.
   * @param links ContentDocumentLink records.
   * @return Set of ContentDocument Ids.
   */
  private static Set<Id> extractDocumentIds(List<ContentDocumentLink> links) {
    Set<Id> documentIds = new Set<Id>();

    for (ContentDocumentLink linkRecord : links) {
      documentIds.add(linkRecord.ContentDocumentId);
    }

    return documentIds;
  }

  /**
   * @description Builds file DTOs from ContentVersion records.
   * @param versions Latest content versions.
   * @return File DTO list.
   */
  private static List<CandidateFileDTO> buildFileDTOs(
    List<ContentVersion> versions
  ) {
    List<ContentVersion> supportedVersions = filterSupportedVersions(versions);

    if (supportedVersions.isEmpty()) {
      return new List<CandidateFileDTO>();
    }

    Map<Id, ContentDistribution> distributionsByVersionId = getOrCreateDistributions(
      supportedVersions
    );

    List<CandidateFileDTO> results = new List<CandidateFileDTO>();

    for (ContentVersion version : supportedVersions) {
      String fileName = getDisplayFileName(version);
      ContentDistribution distribution = distributionsByVersionId.get(
        version.Id
      );

      results.add(buildFileDTO(version, fileName, distribution));
    }

    return results;
  }

  /**
   * @description Keeps only supported PDF ContentVersion records.
   * @param versions Latest content versions.
   * @return Supported versions.
   */
  private static List<ContentVersion> filterSupportedVersions(
    List<ContentVersion> versions
  ) {
    List<ContentVersion> supportedVersions = new List<ContentVersion>();

    for (ContentVersion version : versions) {
      String fileName = getDisplayFileName(version);

      if (isSupportedDocument(fileName)) {
        supportedVersions.add(version);
      }
    }

    return supportedVersions;
  }

  /**
   * @description Gets existing ContentDistribution records or creates them when missing.
   * @param versions Latest content versions.
   * @return Map of ContentVersion Id to ContentDistribution.
   */
  private static Map<Id, ContentDistribution> getOrCreateDistributions(
    List<ContentVersion> versions
  ) {
    Set<Id> versionIds = extractVersionIds(versions);
    Map<Id, ContentDistribution> distributionsByVersionId = queryDistributionsByVersionId(
      versionIds
    );

    List<ContentDistribution> distributionsToInsert = buildMissingDistributions(
      versions,
      distributionsByVersionId
    );

    if (!distributionsToInsert.isEmpty()) {
      Database.insert(distributionsToInsert, AccessLevel.SYSTEM_MODE);
      distributionsByVersionId = queryDistributionsByVersionId(versionIds);
    }

    return distributionsByVersionId;
  }

  /**
   * @description Extracts ContentVersion Ids.
   * @param versions Content versions.
   * @return Set of ContentVersion Ids.
   */
  private static Set<Id> extractVersionIds(List<ContentVersion> versions) {
    Set<Id> versionIds = new Set<Id>();

    for (ContentVersion version : versions) {
      versionIds.add(version.Id);
    }

    return versionIds;
  }

  /**
   * @description Queries ContentDistribution records by ContentVersion Id.
   * @param versionIds ContentVersion Ids.
   * @return Map of ContentVersion Id to ContentDistribution.
   */
  private static Map<Id, ContentDistribution> queryDistributionsByVersionId(
    Set<Id> versionIds
  ) {
    Map<Id, ContentDistribution> distributionsByVersionId = new Map<Id, ContentDistribution>();

    if (versionIds.isEmpty()) {
      return distributionsByVersionId;
    }

    List<ContentDistribution> distributions = [
      SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
      FROM ContentDistribution
      WHERE ContentVersionId IN :versionIds
      WITH SYSTEM_MODE
    ];

    for (ContentDistribution distribution : distributions) {
      distributionsByVersionId.put(distribution.ContentVersionId, distribution);
    }

    return distributionsByVersionId;
  }

  /**
   * @description Builds missing ContentDistribution records.
   * @param versions Latest content versions.
   * @param distributionsByVersionId Existing distributions.
   * @return Distributions to insert.
   */
  private static List<ContentDistribution> buildMissingDistributions(
    List<ContentVersion> versions,
    Map<Id, ContentDistribution> distributionsByVersionId
  ) {
    List<ContentDistribution> distributionsToInsert = new List<ContentDistribution>();

    for (ContentVersion version : versions) {
      if (!distributionsByVersionId.containsKey(version.Id)) {
        distributionsToInsert.add(buildDistribution(version));
      }
    }

    return distributionsToInsert;
  }

  /**
   * @description Builds a ContentDistribution record for a file version.
   * @param version ContentVersion record.
   * @return ContentDistribution record.
   */
  private static ContentDistribution buildDistribution(ContentVersion version) {
    return new ContentDistribution(
      Name = getDisplayFileName(version),
      ContentVersionId = version.Id,
      PreferencesAllowViewInBrowser = true,
      PreferencesAllowOriginalDownload = true,
      PreferencesNotifyOnVisit = false,
      PreferencesPasswordRequired = false
    );
  }

  /**
   * @description Builds a file DTO.
   * @param version Latest content version.
   * @param fileName Display file name.
   * @param distribution Public file distribution.
   * @return Candidate file DTO.
   */
  private static CandidateFileDTO buildFileDTO(
    ContentVersion version,
    String fileName,
    ContentDistribution distribution
  ) {
    CandidateFileDTO dto = new CandidateFileDTO();
    dto.contentDocumentId = version.ContentDocumentId;
    dto.contentVersionId = version.Id;
    dto.title = version.Title;
    dto.fileName = fileName;
    dto.fileType = version.FileType;
    dto.contentSize = version.ContentSize;
    dto.createdDate = version.CreatedDate;
    dto.label = fileName + ' — ' + String.valueOf(version.CreatedDate.date());
    dto.value = String.valueOf(version.ContentDocumentId);

    if (distribution != null) {
      dto.previewUrl = distribution.DistributionPublicUrl;
      dto.downloadUrl = distribution.ContentDownloadUrl;
    }

    return dto;
  }

  /**
   * @description Builds the display file name for a ContentVersion.
   * @param version ContentVersion record.
   * @return Display file name.
   */
  private static String getDisplayFileName(ContentVersion version) {
    if (!String.isBlank(version.PathOnClient)) {
      return version.PathOnClient;
    }

    return version.Title;
  }

  /**
   * @description Checks whether a file name is supported by the candidate portal.
   * @param fileName File name to validate.
   * @return True when the file extension is PDF.
   */
  private static Boolean isSupportedDocument(String fileName) {
    if (String.isBlank(fileName)) {
      return false;
    }

    return fileName.toLowerCase().endsWith('.pdf');
  }

  /**
   * @description Builds a Salesforce File title from the original file name.
   * @param fileName Original file name.
   * @return File title without extension when possible.
   */
  private static String cleanTitle(String fileName) {
    if (String.isBlank(fileName)) {
      return 'Uploaded File';
    }

    Integer dotIndex = fileName.lastIndexOf('.');

    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }

    return fileName;
  }
}
