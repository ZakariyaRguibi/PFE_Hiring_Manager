import { LightningElement } from "lwc";

export default class CandidatePortalHome extends LightningElement {
  get siteBasePath() {
    const pathSegments = window.location.pathname.split("/").filter(Boolean);

    if (!pathSegments.length) {
      return "";
    }

    return `/${pathSegments[0]}`;
  }

  goToJobs() {
    window.location.href = `${this.siteBasePath}/Jobs`;
  }

  goToSpontaneous() {
    window.location.href = `${this.siteBasePath}/spontaneous-application`;
  }

  goToApplications() {
    window.location.href = `${this.siteBasePath}/my-applications`;
  }

  goToProfile() {
    window.location.href = `${this.siteBasePath}/profile`;
  }
}
