import { LightningElement, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";

import searchCandidates from "@salesforce/apex/RecruiterApplicationLookupService.searchCandidates";
import searchOpenJobPositions from "@salesforce/apex/RecruiterApplicationLookupService.searchOpenJobPositions";
import getCandidateFiles from "@salesforce/apex/JobApplicationFileService.getCandidateFiles";
import uploadFileForCandidate from "@salesforce/apex/JobApplicationFileService.uploadFileForCandidate";
import parseCv from "@salesforce/apex/CandidatePortalCvParsingService.parseCv";
import submitManualApplication from "@salesforce/apex/JobApplicationSubmissionService.submitManualApplication";
import getReusableParsingData from "@salesforce/apex/JobApplicationSubmissionService.getReusableParsingData";

const DEFAULT_ERROR = "An error occurred while creating the application.";
const SUPPORTED_FILE_MESSAGE =
  "Please upload the file as a PDF, text file, or image.";

export default class RecruiterJobApplicationSubmission extends NavigationMixin(
  LightningElement
) {
  candidateId;
  candidateSearchTerm = "";
  selectedCandidateLabel;
  candidateSearchResults = [];

  jobPositionId;
  jobSearchTerm = "";
  selectedJobLabel;
  jobSearchResults = [];

  applicationType = "Referral";

  isLoadingFiles = false;
  isSearchingCandidates = false;
  isSearchingJobs = false;
  isUploading = false;
  isParsing = false;
  isSaving = false;

  message;
  messageVariant = "info";

  candidateFiles = [];
  candidateFileOptions = [];

  cvMode = "upload";
  motivationLetterMode = "none";

  selectedCvContentDocumentId;
  selectedMotivationLetterContentDocumentId;

  cvFile;
  cvFileName;
  cvContentDocumentId;

  motivationLetterFile;
  motivationLetterFileName;
  motivationLetterContentDocumentId;

  extractedSkills = "";
  extractedKeywords = "";
  extractedEducation = "";
  extractedExperience = "";

  lastPageReferenceKey;

  @wire(CurrentPageReference)
  handleCurrentPageReference(pageReference) {
    if (!pageReference) {
      return;
    }

    const pageReferenceKey = JSON.stringify({
      type: pageReference.type,
      attributes: pageReference.attributes,
      state: pageReference.state
    });

    if (this.lastPageReferenceKey !== pageReferenceKey) {
      this.lastPageReferenceKey = pageReferenceKey;
      this.resetFormState();
    }
  }

  connectedCallback() {
    this.resetFormState();
  }

  resetFormState() {
    this.candidateId = undefined;
    this.candidateSearchTerm = "";
    this.selectedCandidateLabel = undefined;
    this.candidateSearchResults = [];

    this.jobPositionId = undefined;
    this.jobSearchTerm = "";
    this.selectedJobLabel = undefined;
    this.jobSearchResults = [];

    this.applicationType = "Referral";

    this.isLoadingFiles = false;
    this.isSearchingCandidates = false;
    this.isSearchingJobs = false;
    this.isUploading = false;
    this.isParsing = false;
    this.isSaving = false;

    this.message = undefined;
    this.messageVariant = "info";

    this.candidateFiles = [];
    this.candidateFileOptions = [];

    this.cvMode = "upload";
    this.motivationLetterMode = "none";

    this.selectedCvContentDocumentId = undefined;
    this.selectedMotivationLetterContentDocumentId = undefined;

    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.cvContentDocumentId = undefined;

    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.motivationLetterContentDocumentId = undefined;

    this.extractedSkills = "";
    this.extractedKeywords = "";
    this.extractedEducation = "";
    this.extractedExperience = "";
  }

  get applicationTypeOptions() {
    return [
      { label: "Referral", value: "Referral" },
      { label: "Spontaneous", value: "Spontaneous" }
    ];
  }

  get isReferralApplication() {
    return this.applicationType === "Referral";
  }

  get documentModeOptions() {
    return [
      { label: "Use existing file", value: "existing" },
      { label: "Upload new file", value: "upload" }
    ];
  }

  get motivationLetterModeOptions() {
    if (this.hasExistingFiles) {
      return [
        { label: "None", value: "none" },
        { label: "Use existing file", value: "existing" },
        { label: "Upload new file", value: "upload" }
      ];
    }

    return [
      { label: "None", value: "none" },
      { label: "Upload new file", value: "upload" }
    ];
  }

  get educationOptions() {
    return [
      { label: "-- Select --", value: "" },
      { label: "High School", value: "High School" },
      { label: "Bachelor", value: "Bachelor" },
      { label: "Master", value: "Master" },
      { label: "PhD", value: "PhD" },
      { label: "Other", value: "Other" }
    ];
  }

  get hasCandidateSearchResults() {
    return (
      this.candidateSearchResults && this.candidateSearchResults.length > 0
    );
  }

  get hasJobSearchResults() {
    return this.jobSearchResults && this.jobSearchResults.length > 0;
  }

  get hasExistingFiles() {
    return this.candidateFileOptions && this.candidateFileOptions.length > 0;
  }

  get isCvExistingMode() {
    return this.cvMode === "existing";
  }

  get isCvUploadMode() {
    return this.cvMode === "upload";
  }

  get isMotivationNoneMode() {
    return this.motivationLetterMode === "none";
  }

  get isMotivationExistingMode() {
    return this.motivationLetterMode === "existing";
  }

  get isMotivationUploadMode() {
    return this.motivationLetterMode === "upload";
  }

  get isBusy() {
    return (
      this.isLoadingFiles ||
      this.isSearchingCandidates ||
      this.isSearchingJobs ||
      this.isUploading ||
      this.isParsing ||
      this.isSaving
    );
  }

  get saveButtonLabel() {
    if (this.isUploading) {
      return "Uploading...";
    }

    if (this.isParsing) {
      return "Analyzing CV...";
    }

    if (this.isSaving) {
      return "Saving...";
    }

    return "Save";
  }

  get messageClass() {
    return this.messageVariant === "error"
      ? "slds-notify slds-notify_alert slds-alert_error custom-message"
      : "slds-notify slds-notify_alert slds-alert_success custom-message";
  }

  async handleCandidateSearchInput(event) {
    this.candidateSearchTerm = event.target.value;
    this.candidateId = undefined;
    this.selectedCandidateLabel = undefined;
    this.candidateSearchResults = [];
    this.resetCandidateDocuments();
    this.clearMessage();

    await this.searchCandidateOptions();
  }

  async searchCandidateOptions() {
    if (
      !this.candidateSearchTerm ||
      this.candidateSearchTerm.trim().length < 2
    ) {
      this.candidateSearchResults = [];
      return;
    }

    this.isSearchingCandidates = true;

    try {
      this.candidateSearchResults = await searchCandidates({
        searchTerm: this.candidateSearchTerm
      });
    } catch (error) {
      this.setError(
        this.getErrorMessage(error, "Unable to search candidates.")
      );
      this.candidateSearchResults = [];
    } finally {
      this.isSearchingCandidates = false;
    }
  }

  handleCandidateSelect(event) {
    this.candidateId = event.currentTarget.dataset.id;
    this.selectedCandidateLabel = event.currentTarget.dataset.label;
    this.candidateSearchTerm = this.selectedCandidateLabel;
    this.candidateSearchResults = [];

    this.resetCandidateDocuments();
    this.clearMessage();

    if (this.candidateId) {
      this.loadCandidateFiles();
    }
  }

  async handleJobSearchInput(event) {
    this.jobSearchTerm = event.target.value;
    this.jobPositionId = undefined;
    this.selectedJobLabel = undefined;
    this.jobSearchResults = [];
    this.clearMessage();

    await this.searchJobOptions();
  }

  async searchJobOptions() {
    if (!this.jobSearchTerm || this.jobSearchTerm.trim().length < 2) {
      this.jobSearchResults = [];
      return;
    }

    this.isSearchingJobs = true;

    try {
      this.jobSearchResults = await searchOpenJobPositions({
        searchTerm: this.jobSearchTerm
      });
    } catch (error) {
      this.setError(
        this.getErrorMessage(error, "Unable to search job positions.")
      );
      this.jobSearchResults = [];
    } finally {
      this.isSearchingJobs = false;
    }
  }

  handleJobSelect(event) {
    this.jobPositionId = event.currentTarget.dataset.id;
    this.selectedJobLabel = event.currentTarget.dataset.label;
    this.jobSearchTerm = this.selectedJobLabel;
    this.jobSearchResults = [];
    this.clearMessage();
  }

  handleApplicationTypeChange(event) {
    this.applicationType = event.detail.value;
    this.clearMessage();

    if (!this.isReferralApplication) {
      this.jobPositionId = undefined;
      this.jobSearchTerm = "";
      this.selectedJobLabel = undefined;
      this.jobSearchResults = [];
    }
  }

  async loadCandidateFiles() {
    this.isLoadingFiles = true;
    this.clearMessage();

    try {
      const files = await getCandidateFiles({
        candidateId: this.candidateId
      });

      this.candidateFiles = files || [];

      this.candidateFileOptions = this.candidateFiles.map((file) => {
        return {
          label: file.label || file.fileName || file.title || "Uploaded file",
          value: file.contentDocumentId
        };
      });

      this.cvMode = this.hasExistingFiles ? "existing" : "upload";
      this.motivationLetterMode = "none";
    } catch (error) {
      this.setError(
        this.getErrorMessage(error, "Unable to load candidate files.")
      );

      this.candidateFiles = [];
      this.candidateFileOptions = [];
      this.cvMode = "upload";
      this.motivationLetterMode = "none";
    } finally {
      this.isLoadingFiles = false;
    }
  }

  handleCvModeChange(event) {
    this.cvMode = event.detail.value;
    this.selectedCvContentDocumentId = undefined;
    this.cvContentDocumentId = undefined;
    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.resetParsedFields();
    this.clearMessage();
  }

  handleMotivationLetterModeChange(event) {
    this.motivationLetterMode = event.detail.value;
    this.selectedMotivationLetterContentDocumentId = undefined;
    this.motivationLetterContentDocumentId = undefined;
    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.clearMessage();
  }

  async handleExistingCvChange(event) {
    this.selectedCvContentDocumentId = event.detail.value;
    this.cvContentDocumentId = event.detail.value;
    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.resetParsedFields();
    this.clearMessage();

    await this.loadReusableParsingData();
  }

  handleExistingMotivationLetterChange(event) {
    this.selectedMotivationLetterContentDocumentId = event.detail.value;
    this.motivationLetterContentDocumentId = event.detail.value;
    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.clearMessage();
  }

  handleCvFileChange(event) {
    const file = event.target.files?.[0];

    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.cvContentDocumentId = undefined;
    this.selectedCvContentDocumentId = undefined;
    this.resetParsedFields();
    this.clearMessage();

    if (!file) {
      return;
    }

    if (!this.isSupportedFile(file)) {
      event.target.value = null;
      this.setError(SUPPORTED_FILE_MESSAGE);
      return;
    }

    this.cvFile = file;
    this.cvFileName = file.name;
  }

  handleMotivationLetterFileChange(event) {
    const file = event.target.files?.[0];

    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.motivationLetterContentDocumentId = undefined;
    this.selectedMotivationLetterContentDocumentId = undefined;
    this.clearMessage();

    if (!file) {
      return;
    }

    if (!this.isSupportedFile(file)) {
      event.target.value = null;
      this.setError(SUPPORTED_FILE_MESSAGE);
      return;
    }

    this.motivationLetterFile = file;
    this.motivationLetterFileName = file.name;
  }

  handleExtractedFieldChange(event) {
    const fieldName = event.target.dataset.field;
    const value = event.detail?.value ?? event.target.value;

    if (fieldName === "skills") {
      this.extractedSkills = value;
    } else if (fieldName === "keywords") {
      this.extractedKeywords = value;
    } else if (fieldName === "education") {
      this.extractedEducation = value;
    } else if (fieldName === "experience") {
      this.extractedExperience = value;
    }
  }

  async loadReusableParsingData() {
    if (!this.candidateId || !this.cvContentDocumentId) {
      return;
    }

    this.isParsing = true;

    try {
      const reusableData = await getReusableParsingData({
        candidateId: this.candidateId,
        cvContentDocumentId: this.cvContentDocumentId
      });

      if (!reusableData || !reusableData.found) {
        this.resetParsedFields();
        this.setError(
          "No previous parsed information was found for this existing CV. Please upload it as a new CV so it can be analyzed."
        );
        return;
      }

      this.extractedSkills = reusableData.extractedSkills || "";
      this.extractedKeywords = reusableData.extractedKeywords || "";
      this.extractedEducation = reusableData.extractedEducation || "";
      this.extractedExperience =
        reusableData.extractedExperience !== null &&
        reusableData.extractedExperience !== undefined
          ? reusableData.extractedExperience
          : "";

      this.setSuccess(
        "Existing CV selected. Extracted information was reused from the latest application using this file."
      );
    } catch (error) {
      this.setError(
        this.getErrorMessage(error, "Unable to reuse existing CV information.")
      );
    } finally {
      this.isParsing = false;
    }
  }

  async handleParseCv() {
    this.clearMessage();

    if (!this.validateBaseFields()) {
      return;
    }

    if (!this.validateCvSelection()) {
      return;
    }

    if (this.cvMode === "existing") {
      await this.loadReusableParsingData();
      return;
    }

    try {
      await this.prepareSelectedFiles();

      this.isParsing = true;

      const parsedResult = await parseCv({
        contentDocumentId: this.cvContentDocumentId
      });

      this.extractedSkills = parsedResult.extractedSkills || "";
      this.extractedKeywords = parsedResult.extractedKeywords || "";
      this.extractedEducation = parsedResult.extractedEducation || "";
      this.extractedExperience =
        parsedResult.extractedExperience !== null &&
        parsedResult.extractedExperience !== undefined
          ? parsedResult.extractedExperience
          : "";

      this.setSuccess(
        "CV analyzed successfully. Please review the extracted information."
      );
    } catch (error) {
      this.setError(this.getErrorMessage(error, "Unable to analyze the CV."));
    } finally {
      this.isParsing = false;
    }
  }

  async handleSave() {
    this.clearMessage();

    if (!this.validateBaseFields()) {
      return;
    }

    if (!this.validateCvSelection()) {
      return;
    }

    try {
      await this.prepareSelectedFiles();

      this.isSaving = true;

      const request = {
        candidateId: this.candidateId,
        jobPositionId: this.isReferralApplication ? this.jobPositionId : null,
        applicationType: this.applicationType,
        cvContentDocumentId: this.cvContentDocumentId,
        motivationLetterContentDocumentId:
          this.motivationLetterContentDocumentId,
        extractedSkills: this.extractedSkills,
        extractedKeywords: this.extractedKeywords,
        extractedEducation: this.extractedEducation,
        extractedExperience:
          this.extractedExperience !== null &&
          this.extractedExperience !== undefined &&
          this.extractedExperience !== ""
            ? Number(this.extractedExperience)
            : null,
        reusedExistingCvData: this.cvMode === "existing"
      };

      const result = await submitManualApplication({
        request
      });

      const createdRecordId = result.jobApplicationId;

      this.resetFormState();
      this.navigateToRecord(createdRecordId);
    } catch (error) {
      this.setError(this.getErrorMessage(error, DEFAULT_ERROR));
    } finally {
      this.isSaving = false;
    }
  }

  async prepareSelectedFiles() {
    this.isUploading = true;

    try {
      if (this.cvMode === "existing") {
        this.cvContentDocumentId = this.selectedCvContentDocumentId;
      } else if (!this.cvContentDocumentId) {
        const cvBase64 = await this.readFileAsBase64(this.cvFile);

        const cvResult = await uploadFileForCandidate({
          candidateId: this.candidateId,
          fileName: this.cvFile.name,
          base64Data: cvBase64
        });

        this.cvContentDocumentId = cvResult.contentDocumentId;
      }

      if (this.motivationLetterMode === "none") {
        this.motivationLetterContentDocumentId = null;
      } else if (this.motivationLetterMode === "existing") {
        this.motivationLetterContentDocumentId =
          this.selectedMotivationLetterContentDocumentId || null;
      } else if (
        this.motivationLetterMode === "upload" &&
        this.motivationLetterFile &&
        !this.motivationLetterContentDocumentId
      ) {
        const motivationBase64 = await this.readFileAsBase64(
          this.motivationLetterFile
        );

        const motivationResult = await uploadFileForCandidate({
          candidateId: this.candidateId,
          fileName: this.motivationLetterFile.name,
          base64Data: motivationBase64
        });

        this.motivationLetterContentDocumentId =
          motivationResult.contentDocumentId;
      }
    } finally {
      this.isUploading = false;
    }
  }

  validateBaseFields() {
    if (!this.candidateId) {
      this.setError("Candidate is required.");
      return false;
    }

    if (this.isReferralApplication && !this.jobPositionId) {
      this.setError("Job position is required for referral applications.");
      return false;
    }

    return true;
  }

  validateCvSelection() {
    if (this.cvMode === "existing" && !this.selectedCvContentDocumentId) {
      this.setError("Please select an existing CV or upload a new CV.");
      return false;
    }

    if (this.cvMode === "upload" && !this.cvFile && !this.cvContentDocumentId) {
      this.setError("Please upload a CV before saving.");
      return false;
    }

    return true;
  }

  resetCandidateDocuments() {
    this.candidateFiles = [];
    this.candidateFileOptions = [];

    this.cvMode = "upload";
    this.motivationLetterMode = "none";

    this.selectedCvContentDocumentId = undefined;
    this.selectedMotivationLetterContentDocumentId = undefined;

    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.cvContentDocumentId = undefined;

    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.motivationLetterContentDocumentId = undefined;

    this.resetParsedFields();
    this.clearMessage();
  }

  resetParsedFields() {
    this.extractedSkills = "";
    this.extractedKeywords = "";
    this.extractedEducation = "";
    this.extractedExperience = "";
  }

  readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();

      reader.onload = () => {
        const base64 = reader.result.split(",")[1];
        resolve(base64);
      };

      reader.onerror = () => {
        reject(new Error("Unable to read file."));
      };

      reader.readAsDataURL(file);
    });
  }

  isSupportedFile(file) {
    if (!file || !file.name) {
      return false;
    }

    const supportedExtensions = [".pdf", ".txt", ".png", ".jpg", ".jpeg"];
    const fileName = file.name.toLowerCase();

    return supportedExtensions.some((extension) => {
      return fileName.endsWith(extension);
    });
  }

  setError(message) {
    this.message = message;
    this.messageVariant = "error";
  }

  setSuccess(message) {
    this.message = message;
    this.messageVariant = "success";
  }

  clearMessage() {
    this.message = undefined;
    this.messageVariant = "info";
  }

  getErrorMessage(error, fallbackMessage) {
    return error?.body?.message || error?.message || fallbackMessage;
  }

  navigateToRecord(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "Job_Application__c",
        actionName: "view"
      }
    });
  }

  handleCancel() {
    this.resetFormState();

    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Job_Application__c",
        actionName: "list"
      }
    });
  }
}
