/**
 * @description
 * Service used by recruiters to retrieve and upload Candidate__c files during
 * manual Job_Application__c creation.
 *
 * Supported document formats follow the CV extraction capability:
 * - PDF
 * - Text files
 * - Images
 */
public without sharing class JobApplicationFileService {
  private static final String SUPPORTED_FILE_MESSAGE = 'Only PDF, text, and image files are supported. Please upload a PDF, TXT, PNG, JPG, or JPEG file.';

  private static final Set<String> SUPPORTED_FILE_EXTENSIONS = new Set<String>{
    'pdf',
    'txt',
    'png',
    'jpg',
    'jpeg'
  };

  private static final Set<String> SUPPORTED_SALESFORCE_FILE_TYPES = new Set<String>{
    'PDF',
    'TEXT',
    'TXT',
    'PNG',
    'JPG',
    'JPEG'
  };

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
  }

  @AuraEnabled(cacheable=false)
  public static List<CandidateFileDTO> getCandidateFiles(Id candidateId) {
    validateCandidateId(candidateId);

    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :candidateId
      WITH SYSTEM_MODE
    ];

    if (links.isEmpty()) {
      return new List<CandidateFileDTO>();
    }

    Set<Id> documentIds = new Set<Id>();

    for (ContentDocumentLink linkRecord : links) {
      documentIds.add(linkRecord.ContentDocumentId);
    }

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

  @AuraEnabled
  public static UploadedFileResult uploadFileForCandidate(
    Id candidateId,
    String fileName,
    String base64Data
  ) {
    validateCandidateId(candidateId);
    validateUploadInput(fileName, base64Data);

    ContentVersion contentVersion = new ContentVersion(
      Title = cleanTitle(fileName),
      PathOnClient = fileName,
      VersionData = decodeFileBody(base64Data),
      FirstPublishLocationId = candidateId
    );

    Database.insert(contentVersion, AccessLevel.SYSTEM_MODE);

    ContentVersion insertedVersion = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersion.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    UploadedFileResult result = new UploadedFileResult();
    result.fileName = fileName;
    result.contentVersionId = insertedVersion.Id;
    result.contentDocumentId = insertedVersion.ContentDocumentId;
    result.linkedCandidateId = candidateId;

    return result;
  }

  private static void validateCandidateId(Id candidateId) {
    if (candidateId == null) {
      throw new AuraHandledException('Candidate is required.');
    }

    List<Candidate__c> candidates = [
      SELECT Id
      FROM Candidate__c
      WHERE Id = :candidateId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (candidates.isEmpty()) {
      throw new AuraHandledException('Selected candidate was not found.');
    }
  }

  private static void validateUploadInput(String fileName, String base64Data) {
    if (String.isBlank(fileName)) {
      throw new AuraHandledException('File name is required.');
    }

    if (String.isBlank(base64Data)) {
      throw new AuraHandledException('File content is required.');
    }

    if (!isSupportedFileName(fileName)) {
      throw new AuraHandledException(SUPPORTED_FILE_MESSAGE);
    }
  }

  private static Blob decodeFileBody(String base64Data) {
    try {
      return EncodingUtil.base64Decode(base64Data);
    } catch (Exception decodeException) {
      throw new AuraHandledException('Invalid file content.');
    }
  }

  private static List<CandidateFileDTO> buildFileDTOs(
    List<ContentVersion> versions
  ) {
    List<CandidateFileDTO> results = new List<CandidateFileDTO>();

    for (ContentVersion version : versions) {
      if (!isSupportedVersion(version)) {
        continue;
      }

      String fileName = getDisplayFileName(version);
      results.add(buildFileDTO(version, fileName));
    }

    return results;
  }

  private static CandidateFileDTO buildFileDTO(
    ContentVersion version,
    String fileName
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

    return dto;
  }

  private static String getDisplayFileName(ContentVersion version) {
    if (!String.isBlank(version.PathOnClient)) {
      return version.PathOnClient;
    }

    String title = String.isBlank(version.Title)
      ? 'Uploaded File'
      : version.Title;
    String extension = getExtensionFromFileType(version.FileType);

    if (
      !String.isBlank(extension) &&
      !title.toLowerCase().endsWith('.' + extension)
    ) {
      return title + '.' + extension;
    }

    return title;
  }

  private static Boolean isSupportedVersion(ContentVersion version) {
    if (version == null) {
      return false;
    }

    String normalizedFileType = normalizeFileType(version.FileType);

    if (SUPPORTED_SALESFORCE_FILE_TYPES.contains(normalizedFileType)) {
      return true;
    }

    return isSupportedFileName(version.PathOnClient) ||
      isSupportedFileName(version.Title);
  }

  private static Boolean isSupportedFileName(String fileName) {
    String extension = getFileExtension(fileName);

    if (String.isBlank(extension)) {
      return false;
    }

    return SUPPORTED_FILE_EXTENSIONS.contains(extension);
  }

  private static String getFileExtension(String fileName) {
    if (String.isBlank(fileName) || !fileName.contains('.')) {
      return null;
    }

    Integer dotIndex = fileName.lastIndexOf('.');

    if (dotIndex < 0 || dotIndex == fileName.length() - 1) {
      return null;
    }

    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  private static String normalizeFileType(String fileType) {
    if (String.isBlank(fileType)) {
      return null;
    }

    return fileType.trim().toUpperCase();
  }

  private static String getExtensionFromFileType(String fileType) {
    String normalizedFileType = normalizeFileType(fileType);

    if (normalizedFileType == 'PDF') {
      return 'pdf';
    }

    if (normalizedFileType == 'TEXT' || normalizedFileType == 'TXT') {
      return 'txt';
    }

    if (normalizedFileType == 'PNG') {
      return 'png';
    }

    if (normalizedFileType == 'JPG' || normalizedFileType == 'JPEG') {
      return 'jpg';
    }

    return null;
  }

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
