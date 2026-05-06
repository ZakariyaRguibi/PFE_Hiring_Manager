import { LightningElement } from "lwc";
import isGuest from "@salesforce/user/isGuest";
import talentforceLogo from "@salesforce/resourceUrl/talentforceLogo";

export default class CandidatePortalHeader extends LightningElement {
  isGuestUser = isGuest;
  logoUrl = talentforceLogo;

  get siteBasePath() {
    const pathSegments = window.location.pathname.split("/").filter(Boolean);

    if (!pathSegments.length) {
      return "";
    }

    return `/${pathSegments[0]}`;
  }

  get currentPage() {
    const pathSegments = window.location.pathname.split("/").filter(Boolean);

    if (pathSegments.length <= 1) {
      return "home";
    }

    return pathSegments[1];
  }

  get homeClass() {
    return this.currentPage === "home" || this.currentPage === ""
      ? "nav-link active"
      : "nav-link";
  }

  get jobsClass() {
    return this.currentPage === "jobs" ? "nav-link active" : "nav-link";
  }

  get spontaneousClass() {
    return this.currentPage === "spontaneous-application"
      ? "nav-link active"
      : "nav-link";
  }

  get applicationsClass() {
    return this.currentPage === "my-applications"
      ? "nav-link active"
      : "nav-link";
  }

  get profileClass() {
    return this.currentPage === "profile" ? "nav-link active" : "nav-link";
  }

  getCurrentRelativeUrl() {
    return window.location.pathname + window.location.search;
  }

  goHome() {
    window.location.href = `${this.siteBasePath}/`;
  }

  navigateToPage(event) {
    const page = event.currentTarget.dataset.page;

    if (page === "home") {
      window.location.href = `${this.siteBasePath}/`;
      return;
    }

    window.location.href = `${this.siteBasePath}/${page}`;
  }

  handleLogin() {
    const startUrl = encodeURIComponent(this.getCurrentRelativeUrl());
    window.location.href = `${this.siteBasePath}/login?startURL=${startUrl}`;
  }

  handleRegister() {
    const startUrl = encodeURIComponent(this.getCurrentRelativeUrl());
    window.location.href = `${this.siteBasePath}/SelfRegister?startURL=${startUrl}`;
  }

  handleLogout() {
    window.location.href = `${this.siteBasePath}/secur/logout.jsp`;
  }
}
