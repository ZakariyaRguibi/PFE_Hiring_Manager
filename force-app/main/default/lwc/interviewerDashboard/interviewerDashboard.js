import { LightningElement, wire, track } from 'lwc';
import getDashboardData from '@salesforce/apex/InterviewerDashboardController.getDashboardData';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';

export default class InterviewerDashboard extends NavigationMixin(LightningElement) {
    @track stats = {};
    @track upcomingInterviews = [];
    @track todaysInterviews = [];
    @track pendingScores = [];
    @track alerts = [];

    error;
    wiredDashboardResult;
    isLoading = true;

    getInitials(name) {
        if (!name) return '?';
        const parts = name.trim().split(' ');
        if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
        return name.substring(0, 2).toUpperCase();
    }

    @wire(getDashboardData)
    wiredDashboard(result) {
        this.wiredDashboardResult = result;
        const { data, error } = result;

        if (data) {
            this.stats = data.stats || {};

            this.upcomingInterviews = (data.upcomingInterviews || []).map(iv => ({
                ...iv,
                initials: this.getInitials(iv.candidateName)
            }));

            this.todaysInterviews = data.todaysInterviews || [];

            this.pendingScores = (data.pendingScores || []).map(item => ({
                ...item,
                initials: this.getInitials(item.candidateName)
            }));

            this.alerts = data.alerts || [];
            this.error = undefined;

        } else if (error) {
            this.error = error;
            this.stats = {};
            this.upcomingInterviews = [];
            this.todaysInterviews = [];
            this.pendingScores = [];
            this.alerts = [];
        }

        this.isLoading = false;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredDashboardResult)
            .finally(() => { this.isLoading = false; });
    }

    handleViewInterviews() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Interview__c',
                actionName: 'list'
            }
        });
    }

    handleScoreInterview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Interview__c',
                actionName: 'list'
            }
        });
    }

    handleViewCandidates() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'list'
            }
        });
    }
}