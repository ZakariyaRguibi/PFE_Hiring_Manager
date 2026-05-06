import { LightningElement, wire } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import getOpenJobs from "@salesforce/apex/CandidatePortalJobController.getOpenJobs";
import getCurrentCandidateProfile from "@salesforce/apex/CandidatePortalProfileController.getCurrentCandidateProfile";
import getCandidateFiles from "@salesforce/apex/CandidatePortalFileService.getCandidateFiles";
import uploadTemporaryFile from "@salesforce/apex/CandidatePortalFileService.uploadTemporaryFile";
import parseCv from "@salesforce/apex/CandidatePortalCvParsingService.parseCv";
import submitApplication from "@salesforce/apex/CandidatePortalApplicationService.submitApplication";
import getReusableParsingData from "@salesforce/apex/CandidatePortalApplicationService.getReusableParsingData";

export default class CandidateJobList extends LightningElement {
  jobs = [];
  error;
  isLoading = true;

  selectedJob;
  selectedJobId;
  candidateProfile;

  isJobDetailsModalOpen = false;
  isApplicationModalOpen = false;
  showAuthMessage = false;

  applicationStep = "upload";

  candidateFiles = [];
  candidateFileOptions = [];

  cvMode = "existing";
  motivationLetterMode = "existing";

  selectedCvContentDocumentId;
  selectedMotivationLetterContentDocumentId;

  cvFile;
  motivationLetterFile;

  cvFileName;
  motivationLetterFileName;

  cvContentDocumentId;
  motivationLetterContentDocumentId;

  isUploadingFiles = false;
  isParsingCv = false;
  isSubmittingApplication = false;

  uploadMessage;
  submissionMessage;

  createdJobApplicationId;
  createdJobApplicationName;

  extractedSkills;
  extractedKeywords;
  extractedEducation;
  extractedExperience;
  rawParserResponse;

  @wire(getOpenJobs)
  wiredJobs({ data, error }) {
    this.isLoading = false;

    if (data) {
      this.jobs = data.map((job) => {
        const recordId =
          job.id || job.Id || job.jobId || job.jobPositionId || job.recordId;

        return {
          ...job,
          recordId: recordId
        };
      });

      this.error = undefined;
    } else if (error) {
      console.error("Unable to load jobs:", JSON.stringify(error));
      this.error = error;
      this.jobs = [];
    }
  }

  get hasJobs() {
    return this.jobs && this.jobs.length > 0;
  }

  get hasNoJobs() {
    return (
      !this.isLoading && !this.error && (!this.jobs || this.jobs.length === 0)
    );
  }

  get isUploadStep() {
    return this.applicationStep === "upload";
  }

  get isReviewStep() {
    return this.applicationStep === "review";
  }

  get isSuccessStep() {
    return this.applicationStep === "success";
  }

  get hasExistingFiles() {
    return this.candidateFileOptions && this.candidateFileOptions.length > 0;
  }

  get cvModeOptions() {
    return [
      { label: "Use existing CV", value: "existing" },
      { label: "Upload new CV", value: "upload" }
    ];
  }

  get motivationLetterModeOptions() {
    return [
      { label: "Use existing motivation letter", value: "existing" },
      { label: "Upload new motivation letter", value: "upload" }
    ];
  }

  get isCvExistingMode() {
    return this.cvMode === "existing";
  }

  get isCvUploadMode() {
    return this.cvMode === "upload";
  }

  get isMotivationExistingMode() {
    return this.motivationLetterMode === "existing";
  }

  get isMotivationUploadMode() {
    return this.motivationLetterMode === "upload";
  }

  get nextButtonLabel() {
    if (this.isUploadingFiles) {
      return "Uploading...";
    }

    if (this.isParsingCv) {
      return "Analyzing CV...";
    }

    return "Next";
  }

  get isNextDisabled() {
    return (
      this.isUploadingFiles || this.isParsingCv || this.isSubmittingApplication
    );
  }

  get isApplyDisabled() {
    return this.isSubmittingApplication;
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

  setUserError(message) {
    this.uploadMessage = message;
    this.submissionMessage = message;
  }

  getErrorMessage(error, fallbackMessage) {
    return error?.body?.message || error?.message || fallbackMessage;
  }

  handleViewDetails(event) {
    const jobId = event.currentTarget.dataset.id;

    this.selectedJob = this.jobs.find((job) => job.recordId === jobId);
    this.selectedJobId = jobId;

    if (!this.selectedJobId) {
      this.setUserError(
        "Unable to identify the selected job. Please refresh the page and try again."
      );
      return;
    }

    this.isJobDetailsModalOpen = true;
    this.isApplicationModalOpen = false;
    this.showAuthMessage = false;
    this.uploadMessage = undefined;
    this.submissionMessage = undefined;
  }

  handleCloseModal() {
    this.isJobDetailsModalOpen = false;
    this.isApplicationModalOpen = false;
    this.selectedJob = undefined;
    this.selectedJobId = undefined;
    this.candidateProfile = undefined;
    this.showAuthMessage = false;

    this.applicationStep = "upload";

    this.candidateFiles = [];
    this.candidateFileOptions = [];

    this.cvMode = "existing";
    this.motivationLetterMode = "existing";

    this.selectedCvContentDocumentId = undefined;
    this.selectedMotivationLetterContentDocumentId = undefined;

    this.cvFile = undefined;
    this.motivationLetterFile = undefined;
    this.cvFileName = undefined;
    this.motivationLetterFileName = undefined;
    this.cvContentDocumentId = undefined;
    this.motivationLetterContentDocumentId = undefined;

    this.isUploadingFiles = false;
    this.isParsingCv = false;
    this.isSubmittingApplication = false;

    this.uploadMessage = undefined;
    this.submissionMessage = undefined;

    this.createdJobApplicationId = undefined;
    this.createdJobApplicationName = undefined;

    this.extractedSkills = undefined;
    this.extractedKeywords = undefined;
    this.extractedEducation = undefined;
    this.extractedExperience = undefined;
    this.rawParserResponse = undefined;
  }

  async handleApply() {
    this.showAuthMessage = false;

    if (isGuest) {
      this.showAuthMessage = true;
      return;
    }

    if (!this.selectedJobId && this.selectedJob) {
      this.selectedJobId = this.selectedJob.recordId;
    }

    if (!this.selectedJobId) {
      this.setUserError(
        "Job position is missing. Please close this popup and select the job again."
      );
      return;
    }

    try {
      this.candidateProfile = await getCurrentCandidateProfile();
      await this.loadCandidateFiles();

      this.isJobDetailsModalOpen = false;
      this.isApplicationModalOpen = true;
      this.applicationStep = "upload";
    } catch (error) {
      console.error(
        "Unable to load candidate profile/files:",
        JSON.stringify(error)
      );
      this.showAuthMessage = true;
    }
  }

  async loadCandidateFiles() {
    const files = await getCandidateFiles();

    this.candidateFiles = files || [];
    this.candidateFileOptions = this.candidateFiles.map((file) => {
      return {
        label: file.label || file.fileName || file.title,
        value: file.contentDocumentId
      };
    });

    if (!this.hasExistingFiles) {
      this.cvMode = "upload";
      this.motivationLetterMode = "upload";
    }
  }

  handleCvModeChange(event) {
    this.cvMode = event.detail.value;
    this.cvContentDocumentId = undefined;
    this.uploadMessage = undefined;

    if (this.cvMode === "existing") {
      this.cvFile = undefined;
      this.cvFileName = undefined;
    } else {
      this.selectedCvContentDocumentId = undefined;
    }

    this.resetParsedData();
  }

  handleMotivationLetterModeChange(event) {
    this.motivationLetterMode = event.detail.value;
    this.motivationLetterContentDocumentId = undefined;
    this.uploadMessage = undefined;

    if (this.motivationLetterMode === "existing") {
      this.motivationLetterFile = undefined;
      this.motivationLetterFileName = undefined;
    } else {
      this.selectedMotivationLetterContentDocumentId = undefined;
    }
  }

  handleExistingCvChange(event) {
    this.selectedCvContentDocumentId = event.detail.value;
    this.cvContentDocumentId = event.detail.value;
    this.uploadMessage = undefined;
    this.resetParsedData();
  }

  handleExistingMotivationLetterChange(event) {
    this.selectedMotivationLetterContentDocumentId = event.detail.value;
    this.motivationLetterContentDocumentId = event.detail.value;
    this.uploadMessage = undefined;
  }

  handleCvChange(event) {
    const file = event.target.files?.[0];

    this.cvFile = undefined;
    this.cvFileName = undefined;
    this.cvContentDocumentId = undefined;
    this.uploadMessage = undefined;
    this.submissionMessage = undefined;

    this.resetParsedData();

    if (!file) {
      return;
    }

    if (!this.isPdfFile(file)) {
      event.target.value = null;
      this.setUserError(
        "Please upload your CV in PDF format only. DOC and DOCX files are not supported by the automatic CV analysis."
      );
      return;
    }

    this.cvFile = file;
    this.cvFileName = file.name;
  }

  handleMotivationLetterChange(event) {
    const file = event.target.files?.[0];

    this.motivationLetterFile = undefined;
    this.motivationLetterFileName = undefined;
    this.motivationLetterContentDocumentId = undefined;
    this.uploadMessage = undefined;
    this.submissionMessage = undefined;

    if (!file) {
      return;
    }

    if (!this.isPdfFile(file)) {
      event.target.value = null;
      this.setUserError(
        "Please upload your motivation letter in PDF format only."
      );
      return;
    }

    this.motivationLetterFile = file;
    this.motivationLetterFileName = file.name;
  }

  resetParsedData() {
    this.extractedSkills = undefined;
    this.extractedKeywords = undefined;
    this.extractedEducation = undefined;
    this.extractedExperience = undefined;
    this.rawParserResponse = undefined;
    this.applicationStep = "upload";
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

  async handleNext() {
    this.uploadMessage = undefined;
    this.submissionMessage = undefined;

    if (this.cvMode === "existing" && !this.selectedCvContentDocumentId) {
      this.setUserError(
        "Please select an existing CV or choose Upload new CV."
      );
      return;
    }

    if (this.cvMode === "upload" && !this.cvFile) {
      this.setUserError("Please upload your CV before continuing.");
      return;
    }

    this.isUploadingFiles = true;
    this.isParsingCv = false;

    try {
      await this.prepareSelectedFiles();

      this.isUploadingFiles = false;

      if (this.cvMode === "existing") {
        await this.loadReusableParsingDataOrStop();
        this.applicationStep = "review";
        return;
      }

      await this.parseUploadedCv();
      this.applicationStep = "review";
    } catch (error) {
      console.error("Application step failed:", JSON.stringify(error));

      this.setUserError(
        this.getErrorMessage(
          error,
          "An error occurred while processing your application."
        )
      );
    } finally {
      this.isUploadingFiles = false;
      this.isParsingCv = false;
    }
  }

  async prepareSelectedFiles() {
    if (this.cvMode === "existing") {
      this.cvContentDocumentId = this.selectedCvContentDocumentId;
    } else if (!this.cvContentDocumentId) {
      if (!this.isPdfFile(this.cvFile)) {
        throw new Error(
          "Please upload your CV in PDF format only. DOC and DOCX files are not supported by the automatic CV analysis."
        );
      }

      const cvBase64 = await this.readFileAsBase64(this.cvFile);
      const cvResult = await uploadTemporaryFile({
        fileName: this.cvFile.name,
        base64Data: cvBase64
      });

      this.cvContentDocumentId = cvResult.contentDocumentId;
    }

    if (this.motivationLetterMode === "existing") {
      this.motivationLetterContentDocumentId =
        this.selectedMotivationLetterContentDocumentId || null;
    } else if (
      this.motivationLetterFile &&
      !this.motivationLetterContentDocumentId
    ) {
      if (!this.isPdfFile(this.motivationLetterFile)) {
        throw new Error(
          "Please upload your motivation letter in PDF format only."
        );
      }

      const motivationBase64 = await this.readFileAsBase64(
        this.motivationLetterFile
      );

      const motivationResult = await uploadTemporaryFile({
        fileName: this.motivationLetterFile.name,
        base64Data: motivationBase64
      });

      this.motivationLetterContentDocumentId =
        motivationResult.contentDocumentId;
    }
  }

  async loadReusableParsingDataOrStop() {
    const reusableParsingData = await getReusableParsingData({
      cvContentDocumentId: this.cvContentDocumentId
    });

    if (!reusableParsingData || !reusableParsingData.found) {
      this.resetParsedData();
      this.uploadMessage =
        "No previous parsed information was found for this existing CV. Please upload it as a new CV so it can be analyzed.";
      throw new Error(this.uploadMessage);
    }

    this.extractedSkills = reusableParsingData.extractedSkills || "";
    this.extractedKeywords = reusableParsingData.extractedKeywords || "";
    this.extractedEducation = reusableParsingData.extractedEducation || "";
    this.extractedExperience =
      reusableParsingData.extractedExperience !== null &&
      reusableParsingData.extractedExperience !== undefined
        ? reusableParsingData.extractedExperience
        : "";

    this.rawParserResponse = undefined;

    this.uploadMessage =
      "Existing CV selected. Extracted information was reused from your latest application using this file.";
  }

  async parseUploadedCv() {
    this.isParsingCv = true;

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

    this.rawParserResponse = parsedResult.rawResponse;

    this.uploadMessage =
      "CV analyzed successfully. Please review the extracted information.";
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

  handleBackToUpload() {
    this.applicationStep = "upload";
    this.uploadMessage = undefined;
    this.submissionMessage = undefined;
  }

  async handleFinalApply() {
    const finalJobId = this.selectedJobId || this.selectedJob?.recordId;

    if (!finalJobId) {
      this.setUserError(
        "Job position is missing. Please close this popup and select the job again."
      );
      return;
    }

    this.isSubmittingApplication = true;
    this.submissionMessage = undefined;

    try {
      const requestPayload = {
        jobPositionId: finalJobId,
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

      const result = await submitApplication({
        request: requestPayload
      });

      this.createdJobApplicationId = result.jobApplicationId;
      this.createdJobApplicationName = result.applicationName;

      this.submissionMessage =
        "Application submitted successfully. Your application reference is " +
        result.applicationName +
        ". You can now track your application from your candidate space.";

      this.applicationStep = "success";

      window.location.assign(`${this.getSiteBasePath()}/my-applications`);
    } catch (error) {
      console.error("Application submission failed:", JSON.stringify(error));

      this.setUserError(
        this.getErrorMessage(error, "Application submission failed.")
      );
    } finally {
      this.isSubmittingApplication = false;
    }
  }

  getCurrentRelativeUrl() {
    return window.location.pathname + window.location.search;
  }

  getSiteBasePath() {
    const pathSegments = window.location.pathname.split("/").filter(Boolean);

    if (!pathSegments.length) {
      return "";
    }

    return `/${pathSegments[0]}`;
  }

  handleLogin() {
    const startUrl = encodeURIComponent(this.getCurrentRelativeUrl());
    window.location.href = `${this.getSiteBasePath()}/login?startURL=${startUrl}`;
  }

  handleRegister() {
    const startUrl = encodeURIComponent(this.getCurrentRelativeUrl());
    window.location.href = `${this.getSiteBasePath()}/SelfRegister?startURL=${startUrl}`;
  }

  isPdfFile(file) {
    if (!file || !file.name) {
      return false;
    }

    return file.name.toLowerCase().endsWith(".pdf");
  }
}
