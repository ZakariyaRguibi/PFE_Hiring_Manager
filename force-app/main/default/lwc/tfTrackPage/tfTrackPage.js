import { LightningElement, track } from 'lwc';
import isGuest from '@salesforce/apex/TfTrackController.isGuest';
import getMyApplications from '@salesforce/apex/TfTrackController.getMyApplications';
import getMyInterviews from '@salesforce/apex/TfTrackController.getMyInterviews';
import withdrawMyApplication from '@salesforce/apex/TfTrackController.withdrawMyApplication';

export default class TfTrackPage extends LightningElement {
  @track loading = true;
  @track guestUser = true;
  @track applications = [];
  @track interviews = [];
  @track withdrawing = false;
  @track errorMessage = '';

  connectedCallback() {
    this.loadData();
  }

  get hasApplications() {
    return Array.isArray(this.applications) && this.applications.length > 0;
  }

  get applicationCount() {
    return Array.isArray(this.applications) ? this.applications.length : 0;
  }

  get applicationCards() {
    const now = new Date();
    const interviewsByOpportunity = new Map();

    (this.interviews || []).forEach(interview => {
      const key = interview.opportunityId;
      if (!key) return;

      const interviewDate = interview.interviewDate ? new Date(interview.interviewDate) : null;
      const isUpcoming = interviewDate ? interviewDate.getTime() > now.getTime() : false;

      const formatted = {
        ...interview,
        displayDate: this.formatDate(interview.interviewDate),
        isUpcoming,
        timeStatus: isUpcoming ? 'Upcoming' : 'Completed / Past',
        dotClass: isUpcoming ? 'timelineDot upcoming' : 'timelineDot past'
      };

      if (!interviewsByOpportunity.has(key)) {
        interviewsByOpportunity.set(key, []);
      }
      interviewsByOpportunity.get(key).push(formatted);
    });

    return (this.applications || []).map(app => {
      const appInterviews = interviewsByOpportunity.get(app.opportunityId) || [];
      const hasUpcomingInterviews = appInterviews.some(i => i.isUpcoming === true);
      const isWithdrawn = (app.stageName || '').toLowerCase() === 'withdrawn';

      return {
        ...app,
        interviews: appInterviews,
        interviewsCount: appInterviews.length,
        hasInterviews: appInterviews.length > 0,
        hasUpcomingInterviews,
        showWithdrawButton: hasUpcomingInterviews && !isWithdrawn
      };
    });
  }

  async loadData() {
    this.loading = true;
    this.errorMessage = '';

    try {
      this.guestUser = await isGuest();

      if (!this.guestUser) {
        const [applications, interviews] = await Promise.all([
          getMyApplications(),
          getMyInterviews()
        ]);

        this.applications = applications || [];
        this.interviews = interviews || [];
      }
    } catch (e) {
      this.guestUser = true;
      this.applications = [];
      this.interviews = [];
      this.errorMessage = this.extractError(e);
    } finally {
      this.loading = false;
    }
  }

  async handleWithdraw(event) {
    const opportunityId = event.currentTarget.dataset.id;
    const jobName = event.currentTarget.dataset.job || 'this application';

    const confirmed = window.confirm(
      `Are you sure you want to withdraw your application for ${jobName}? This will mark the whole application as withdrawn.`
    );

    if (!confirmed) return;

    this.withdrawing = true;
    this.errorMessage = '';

    try {
      await withdrawMyApplication({ opportunityId });
      await this.loadData();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    } finally {
      this.withdrawing = false;
    }
  }

  formatDate(value) {
    if (!value) return '';
    try {
      return new Intl.DateTimeFormat('en-GB', {
        year: 'numeric',
        month: 'short',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
      }).format(new Date(value));
    } catch (_) {
      return value;
    }
  }

  extractError(e) {
    return e?.body?.message || e?.message || 'Something went wrong.';
  }
}