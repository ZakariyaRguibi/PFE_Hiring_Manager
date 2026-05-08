import { LightningElement } from "lwc";
import getCurrentCandidateProfile from "@salesforce/apex/CandidatePortalProfileController.getCurrentCandidateProfile";
import getCandidateFiles from "@salesforce/apex/CandidatePortalFileService.getCandidateFiles";

const DEFAULT_PROFILE_ERROR =
  "No candidate profile is linked to your account. Please contact support.";
const DEFAULT_FILE_ERROR = "Unable to load uploaded files.";

export default class CandidateProfile extends LightningElement {
  isLoading = true;
  errorMessage;
  fileErrorMessage;

  candidateProfile;
  candidateFiles = [];

  connectedCallback() {
    this.loadProfile();
  }

  async loadProfile() {
    this.isLoading = true;
    this.errorMessage = undefined;
    this.fileErrorMessage = undefined;
    this.candidateProfile = undefined;
    this.candidateFiles = [];

    try {
      const profile = await getCurrentCandidateProfile();

      if (!profile || profile.hasProfile === false) {
        this.errorMessage = DEFAULT_PROFILE_ERROR;
        return;
      }

      this.candidateProfile = profile;
      await this.loadCandidateFiles();
    } catch (error) {
      this.errorMessage =
        error?.body?.message ||
        error?.message ||
        "Unable to load your profile.";
    } finally {
      this.isLoading = false;
    }
  }

  async loadCandidateFiles() {
    try {
      const files = await getCandidateFiles();

      this.candidateFiles = (files || []).map((file) => {
        const label =
          file.label || file.fileName || file.title || "Uploaded file";

        return {
          ...file,
          label,
          previewUrl: this.buildPreviewUrl(file),
          downloadUrl: this.buildDownloadUrl(file)
        };
      });
    } catch (error) {
      this.fileErrorMessage =
        error?.body?.message || error?.message || DEFAULT_FILE_ERROR;

      this.candidateFiles = [];
    }
  }

  buildPreviewUrl(file) {
    return file?.previewUrl || file?.downloadUrl;
  }

  buildDownloadUrl(file) {
    return file?.downloadUrl || file?.previewUrl;
  }

  handlePreviewFile(event) {
    const url = event.currentTarget.dataset.url;

    if (!url) {
      this.fileErrorMessage = "Unable to preview this file.";
      return;
    }

    window.open(url, "_blank", "noopener,noreferrer");
  }

  handleDownloadFile(event) {
    const url = event.currentTarget.dataset.url;

    if (!url) {
      this.fileErrorMessage = "Unable to download this file.";
      return;
    }

    window.open(url, "_blank", "noopener,noreferrer");
  }

  get showProfile() {
    return !this.isLoading && !this.errorMessage && this.candidateProfile;
  }

  get showError() {
    return !this.isLoading && this.errorMessage;
  }

  get hasFiles() {
    return this.candidateFiles && this.candidateFiles.length > 0;
  }

  get showFileError() {
    return Boolean(this.fileErrorMessage);
  }
}
