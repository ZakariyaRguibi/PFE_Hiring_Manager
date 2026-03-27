import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import INITIAL_SCORE from '@salesforce/schema/Lead.Initial_Score__c';
import EXPERIENCE_SCORE from '@salesforce/schema/Lead.Experience_Score__c';
import EDUCATION_SCORE from '@salesforce/schema/Lead.Education_Score__c';

const FIELDS = [
    INITIAL_SCORE,
    EXPERIENCE_SCORE,
    EDUCATION_SCORE
];

export default class CandidateScoreBreakdown extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    lead;

    normalize(value) {
        const num = Number(value);
        if (isNaN(num)) return 0;
        if (num < 0) return 0;
        if (num > 100) return 100;
        return Math.round(num);
    }

    roundToStep(value) {
        return Math.round(value / 10) * 10;
    }

    get initialScore() {
        return this.normalize(getFieldValue(this.lead.data, INITIAL_SCORE));
    }

    get experienceScore() {
        return this.normalize(getFieldValue(this.lead.data, EXPERIENCE_SCORE));
    }

    get educationScore() {
        return this.normalize(getFieldValue(this.lead.data, EDUCATION_SCORE));
    }

    get overallScore() {
        return Math.round(
            (this.initialScore + this.experienceScore + this.educationScore) / 3
        );
    }

    get overallLabel() {
        if (this.overallScore >= 70) return 'Strong Profile';
        if (this.overallScore >= 50) return 'Average Profile';
        return 'Needs Review';
    }

    get overallBadgeClass() {
        if (this.overallScore >= 70) return 'overallBadge strongBadge';
        if (this.overallScore >= 50) return 'overallBadge mediumBadge';
        return 'overallBadge weakBadge';
    }

    get initialBarClass() {
        return `barFill high ${this.widthClass(this.initialScore)}`;
    }

    get experienceBarClass() {
        return `barFill ${this.toneClass(this.experienceScore)} ${this.widthClass(this.experienceScore)}`;
    }

    get educationBarClass() {
        return `barFill ${this.toneClass(this.educationScore)} ${this.widthClass(this.educationScore)}`;
    }

    toneClass(score) {
        if (score >= 70) return 'high';
        if (score >= 50) return 'medium';
        return 'low';
    }

    widthClass(score) {
        return `w-${this.roundToStep(score)}`;
    }
}