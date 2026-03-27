import { LightningElement, api, wire } from 'lwc';
import getExistingAccountInfo from '@salesforce/apex/LeadMatchController.getExistingAccountInfo';

export default class LeadExistingAccountBanner extends LightningElement {
  @api recordId;

  info;
  error;

  @wire(getExistingAccountInfo, { leadId: '$recordId' })
  wiredInfo({ data, error }) {
    if (data) {
      this.info = data;
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.info = undefined;
    }
  }

  get showBanner() {
    return this.info?.hasExisting;
  }
}