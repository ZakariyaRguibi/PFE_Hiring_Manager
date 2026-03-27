import { LightningElement, track } from 'lwc';
import getDepartmentOptions from '@salesforce/apex/TfHomeController.getDepartmentOptions';
import getFeaturedOpenJobs from '@salesforce/apex/TfHomeController.getFeaturedOpenJobs';

export default class TfHomeContent extends LightningElement {
  keyword = '';
  location = '';
  department = '';

  @track departmentOptions = [];
  @track featuredJobs = [];
  @track loadingJobs = true;
  @track jobsError;

  connectedCallback() {
    this.loadDepartments();
    this.loadFeaturedJobs();
  }

  get noJobs() {
    return Array.isArray(this.featuredJobs) && this.featuredJobs.length === 0 && !this.loadingJobs && !this.jobsError;
  }

  async loadDepartments() {
    try {
      const values = await getDepartmentOptions();
      this.departmentOptions = (values || []).map(v => ({ label: v, value: v }));
    } catch (e) {
      this.departmentOptions = [];
    }
  }

  async loadFeaturedJobs() {
    this.loadingJobs = true;
    this.jobsError = null;
    try {
      const jobs = await getFeaturedOpenJobs({ limitSize: 6 });
      this.featuredJobs = (jobs || []).map(job => ({
        ...job,
        link: `/recruitemntportal/s/jobs?jobId=${job.Id}`
      }));
    } catch (e) {
      this.featuredJobs = [];
      this.jobsError = e?.body?.message ? e.body.message : 'Error loading featured jobs';
    } finally {
      this.loadingJobs = false;
    }
  }

  onKeyword = (e) => { this.keyword = e.target.value; };
  onLocation = (e) => { this.location = e.target.value; };
  onDepartment = (e) => { this.department = e.target.value; };

  clear() {
    this.keyword = '';
    this.location = '';
    this.department = '';
  }

  goJobs() {
    const params = new URLSearchParams();
    if (this.keyword) params.set('keyword', this.keyword);
    if (this.location) params.set('location', this.location);
    if (this.department) params.set('department', this.department);

    window.location.href = `/recruitemntportal/s/jobs${params.toString() ? '?' + params.toString() : ''}`;
  }
}