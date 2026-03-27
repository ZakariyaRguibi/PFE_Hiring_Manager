import { LightningElement, api, track } from 'lwc';
import getJobById from '@salesforce/apex/TfJobsController.getJobById';

export default class TfJobDetailsModal extends LightningElement {
  @api jobId;

  @track job = {};
  @track loading = true;
  @track error;

  connectedCallback() {
    this.load();
  }

  get jobReady() {
    return !this.loading && !this.error && this.job && this.job.Id;
  }

  async load() {
    this.loading = true;
    this.error = null;

    try {
      this.job = await getJobById({ jobId: this.jobId });
    } catch (e) {
      this.job = {};
      this.error = e?.body?.message ? e.body.message : 'Error loading job details';
    } finally {
      this.loading = false;
    }
  }

  close() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  apply() {
    this.dispatchEvent(new CustomEvent('apply'));
  }

  closeIfBackdrop(e) {
    if (e.target.classList.contains('backdrop')) this.close();
  }
}