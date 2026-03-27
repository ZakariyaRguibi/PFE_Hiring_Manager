import { LightningElement, api, wire } from 'lwc';
import getCandidatePool from '@salesforce/apex/OpportunityCandidatePoolController.getCandidatePool';

export default class OpportunityCandidatePool extends LightningElement {

    @api recordId;

    data;
    error;
    isLoading = true;

    @wire(getCandidatePool, { recordId: '$recordId' })
    wiredPool({ error, data }) {

        // 🔥 FIX: prevent early call issue
        if (!this.recordId) {
            return;
        }

        this.isLoading = false;

        if (data) {
            this.data = this.normalizeData(data);
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.data = undefined;
            console.error(error);
        }
    }

    normalizeData(data) {
        return {
            ...data,
            acceptedPool: this.addUrls(data.acceptedPool),
            shortlisted: this.addUrls(data.shortlisted),
            hired: this.addUrls(data.hired),
            rejected: this.addUrls(data.rejected)
        };
    }

    addUrls(rows) {
        return (rows || []).map(r => ({
            ...r,
            recordUrl: '/lightning/r/Opportunity/' + r.id + '/view'
        }));
    }

    get hasData() { return this.data; }
    get errorMessage() { return this.error?.body?.message || 'Error loading data'; }

    get jobPositionName() { return this.data?.jobPositionName || ''; }
    get openPositions() { return this.data?.openPositions || 0; }
    get filledPositions() { return this.data?.filledPositions || 0; }
    get remainingPositions() { return this.data?.remainingPositions || 0; }
    get totalApplicants() { return this.data?.totalApplicants || 0; }

    get acceptedPool() { return this.data?.acceptedPool || []; }
    get shortlisted() { return this.data?.shortlisted || []; }
    get hired() { return this.data?.hired || []; }
    get rejected() { return this.data?.rejected || []; }
}