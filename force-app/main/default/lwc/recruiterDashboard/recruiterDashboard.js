import { LightningElement, wire, track } from 'lwc';
import getDashboardData from '@salesforce/apex/RecruiterDashboardController.getDashboardData';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';

export default class RecruiterDashboard extends NavigationMixin(LightningElement) {
    @track stats = {};
    @track pipeline = [];
    @track topCandidates = [];
    @track interviews = [];
    @track recentOpportunities = [];
    @track alerts = [];

    error;
    wiredDashboardResult;
    isLoading = true;

    // ── Helper ──
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

            this.pipeline = (data.pipeline || []).map(item => ({
    ...item,
    style: 'width: ' + (item.percentage || 0) + '%;'
}));

            this.topCandidates = (data.topCandidates || []).map(c => ({
                ...c,
                initials: this.getInitials(c.name)
            }));

            this.interviews = data.interviews || [];

            this.recentOpportunities = (data.recentOpportunities || []).map(opp => ({
                ...opp,
                initials: this.getInitials(opp.name)
            }));

            this.alerts = data.alerts || [];
            this.error = undefined;

        } else if (error) {
            this.error = error;
            this.stats = {};
            this.pipeline = [];
            this.topCandidates = [];
            this.interviews = [];
            this.recentOpportunities = [];
            this.alerts = [];
        }

        this.isLoading = false;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredDashboardResult)
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCreateOpportunity() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            }
        });
    }

    handleScheduleInterview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Interview__c',
                actionName: 'new'
            }
        });
    }

    handleReviewOpportunities() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'list'
            }
        });
    }
}