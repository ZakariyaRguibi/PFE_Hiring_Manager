import { LightningElement, wire } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import getOpenJobs from "@salesforce/apex/CandidatePortalJobController.getOpenJobs";

export default class CandidateJobList extends LightningElement {
  jobs = [];
  error;
  isLoading = true;

  selectedJob;
  selectedJobId;

  isJobDetailsModalOpen = false;
  isApplicationModalOpen = false;
  showAuthMessage = false;

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
      // eslint-disable-next-line no-console
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

  handleViewDetails(event) {
    const jobId = event.currentTarget.dataset.id;

    this.selectedJob = this.jobs.find((job) => job.recordId === jobId);
    this.selectedJobId = jobId;

    if (!this.selectedJobId) {
      // eslint-disable-next-line no-alert
      alert(
        "Unable to identify the selected job. Please refresh the page and try again."
      );
      return;
    }

    this.isJobDetailsModalOpen = true;
    this.isApplicationModalOpen = false;
    this.showAuthMessage = false;
  }

  handleCloseModal() {
    this.isJobDetailsModalOpen = false;
    this.isApplicationModalOpen = false;
    this.selectedJob = undefined;
    this.selectedJobId = undefined;
    this.showAuthMessage = false;
  }

  handleApply() {
    this.showAuthMessage = false;

    if (isGuest) {
      this.showAuthMessage = true;
      return;
    }

    this.isJobDetailsModalOpen = false;
    this.isApplicationModalOpen = true;
  }

  handleLogin() {
    window.location.href = "/talentforce/login";
  }

  handleRegister() {
    window.location.href = "/talentforce/SelfRegister";
  }
}
