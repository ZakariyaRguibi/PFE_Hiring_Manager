import { LightningElement, track } from 'lwc';
import getDepartmentOptions from '@salesforce/apex/TfJobsController.getDepartmentOptions';
import getEmploymentTypeOptions from '@salesforce/apex/TfJobsController.getEmploymentTypeOptions';
import searchOpenJobs from '@salesforce/apex/TfJobsController.searchOpenJobs';

export default class TfJobsPage extends LightningElement {
  keyword = '';
  location = '';
  department = '';
  employmentType = '';

  @track departmentOptions = [];
  @track employmentTypeOptions = [];

  @track jobs = [];
  @track loading = true;
  @track error;

  @track showDetails = false;
  @track showApply = false;
  @track selectedJobId;

  pendingJobIdFromUrl = null;

  connectedCallback() {
    this.initFromUrl();
    this.loadPicklists();
    this.search();
  }

  initFromUrl() {
    try {
      const params = new URLSearchParams(window.location.search);
      this.keyword = params.get('keyword') || '';
      this.location = params.get('location') || '';
      this.department = params.get('department') || '';
      this.employmentType = params.get('employmentType') || '';
      this.pendingJobIdFromUrl = params.get('jobId') || null;
    } catch (_) {
      // ignore
    }
  }

  get resultsCount() {
    return Array.isArray(this.jobs) ? this.jobs.length : 0;
  }

  get noResults() {
    return !this.loading && !this.error && Array.isArray(this.jobs) && this.jobs.length === 0;
  }

  async loadPicklists() {
    try {
      const deps = await getDepartmentOptions();
      this.departmentOptions = (deps || []).map(v => ({ label: v, value: v }));
    } catch (_) {
      this.departmentOptions = [];
    }

    try {
      const types = await getEmploymentTypeOptions();
      this.employmentTypeOptions = (types || []).map(v => ({ label: v, value: v }));
    } catch (_) {
      this.employmentTypeOptions = [];
    }
  }

  onKeyword = (e) => { this.keyword = e.target.value; };
  onLocation = (e) => { this.location = e.target.value; };
  onDepartment = (e) => { this.department = e.target.value; };
  onEmploymentType = (e) => { this.employmentType = e.target.value; };

  clear = () => {
    this.keyword = '';
    this.location = '';
    this.department = '';
    this.employmentType = '';
    this.pendingJobIdFromUrl = null;
    this.search();
  };

  search = async () => {
    this.loading = true;
    this.error = null;

    try {
      this.jobs = await searchOpenJobs({
        keyword: this.keyword,
        location: this.location,
        department: this.department,
        employmentType: this.employmentType
      });

      if (this.pendingJobIdFromUrl) {
        const match = this.jobs.find(job => job.Id === this.pendingJobIdFromUrl);
        if (match) {
          this.selectedJobId = this.pendingJobIdFromUrl;
          this.showDetails = true;
        }
        this.pendingJobIdFromUrl = null;
      }
    } catch (e) {
      this.jobs = [];
      this.error = e?.body?.message ? e.body.message : 'Error loading jobs';
    } finally {
      this.loading = false;
    }
  };

  openDetails = (e) => {
    const jobId = e.currentTarget.dataset.id;
    this.selectedJobId = jobId;
    this.showDetails = true;
  };

  closeDetails = () => {
    this.showDetails = false;
  };

  openApply = () => {
    this.showDetails = false;
    this.showApply = true;
  };

  closeApply = () => {
    this.showApply = false;
  };
}