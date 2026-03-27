import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import QUALIFICATION_STATUS from '@salesforce/schema/Lead.Qualification_Status__c';
import LEAD_STATUS from '@salesforce/schema/Lead.Status';
import JOB_POSITION_NAME from '@salesforce/schema/Lead.Applied_Job_Position__r.Name';

const FIELDS = [
    QUALIFICATION_STATUS,
    LEAD_STATUS,
    JOB_POSITION_NAME
];

export default class QualificationStatusCard extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    lead;

    get qualificationStatus() {
        return getFieldValue(this.lead.data, QUALIFICATION_STATUS);
    }

    get leadStatus() {
        return getFieldValue(this.lead.data, LEAD_STATUS) || '—';
    }

    get jobPositionName() {
        return getFieldValue(this.lead.data, JOB_POSITION_NAME) || 'Not specified';
    }

    get qualificationStatusLabel() {
        return this.qualificationStatus || 'Not Evaluated';
    }

    get badgeClass() {
        switch (this.qualificationStatus) {
            case 'Qualified':
                return 'badge success';
            case 'Manual Review':
                return 'badge warning';
            case 'Disqualified':
                return 'badge danger';
            default:
                return 'badge neutral';
        }
    }

    get recommendationMessage() {
        switch (this.qualificationStatus) {
            case 'Qualified':
                return 'Ready for next review step';
            case 'Manual Review':
                return 'Needs recruiter validation';
            case 'Disqualified':
                return 'Does not currently meet criteria';
            default:
                return 'Waiting for qualification result';
        }
    }

    get messageClass() {
        switch (this.qualificationStatus) {
            case 'Qualified':
                return 'message successText';
            case 'Manual Review':
                return 'message warningText';
            case 'Disqualified':
                return 'message dangerText';
            default:
                return 'message neutralText';
        }
    }
}