import { LightningElement, api, track } from 'lwc';
import getJobById from '@salesforce/apex/TfJobsController.getJobById';
import getMyCandidateProfile from '@salesforce/apex/TfTrackController.getMyCandidateProfile';

export default class TfApplyModal extends LightningElement {
  @api jobId;
  @api flowApiName;
  @api flowJobvarName;

  @track job = {};
  @track candidateProfile = {};
  @track loading = true;
  @track flowReady = false;

  connectedCallback() {
    this.initialize();
  }

  async initialize() {
    this.loading = true;
    this.flowReady = false;

    try {
      await Promise.all([
        this.loadJob(),
        this.loadCandidateProfile()
      ]);
    } finally {
      this.loading = false;

      // render flow only after all values are loaded
      this.flowReady = true;
    }
  }

  async loadJob() {
    try {
      this.job = await getJobById({ jobId: this.jobId });
    } catch (e) {
      this.job = {};
    }
  }

  async loadCandidateProfile() {
    try {
      const profile = await getMyCandidateProfile();
      this.candidateProfile = profile || {};
    } catch (e) {
      this.candidateProfile = {};
    }
  }

  get jobReady() {
    return this.job && this.job.Id;
  }

  get showLocationDot() {
    return this.job?.Location__c && this.job?.Department__c;
  }

  get showDepartmentDot() {
    return (this.job?.Location__c || this.job?.Department__c) && this.job?.Employment_Type__c;
  }

  get flowInputs() {
    return [
      {
        name: this.flowJobvarName,
        type: 'String',
        value: this.jobId
      },
      {
        name: 'varJobTitle',
        type: 'String',
        value: this.job?.Name || ''
      },
      {
        name: 'varJobLocation',
        type: 'String',
        value: this.job?.Location__c || ''
      },
      {
        name: 'varJobDepartment',
        type: 'String',
        value: this.job?.Department__c || ''
      },
      {
        name: 'varJobEmploymentType',
        type: 'String',
        value: this.job?.Employment_Type__c || ''
      },
      {
        name: 'varPrefillFirstName',
        type: 'String',
        value: this.candidateProfile?.firstName || ''
      },
      {
        name: 'varPrefillLastName',
        type: 'String',
        value: this.candidateProfile?.lastName || ''
      },
      {
        name: 'varPrefillEmail',
        type: 'String',
        value: this.candidateProfile?.email || ''
      },
      {
        name: 'varPrefillPhone',
        type: 'String',
        value: this.candidateProfile?.phone || ''
      }
    ];
  }

  close() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  closeIfBackdrop(e) {
    if (e.target.classList.contains('backdrop')) {
      this.close();
    }
  }

  stopPropagation(e) {
    e.stopPropagation();
  }

  handleStatusChange(event) {
    if (event.detail.status === 'FINISHED') {
      this.close();
    }
  }
}