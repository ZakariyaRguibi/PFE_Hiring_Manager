import { LightningElement, track } from 'lwc';
import getOpenJobsCount from '@salesforce/apex/TfHomeController.getOpenJobsCount';

export default class TfHomeSidebar extends LightningElement {
  @track openCount;
  @track countReady = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.openCount = await getOpenJobsCount();
    } catch (e) {
      this.openCount = null;
    } finally {
      this.countReady = true;
    }
  }
}