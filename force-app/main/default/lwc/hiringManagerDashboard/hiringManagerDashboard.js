import { LightningElement, wire, track } from 'lwc';
import getDashboardData from '@salesforce/apex/HiringManagerDashboardController.getDashboardData';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';

export default class HiringManagerDashboard extends NavigationMixin(LightningElement) {
    @track stats = {};
    @track approvalQueue = [];
    @track topCandidates = [];
    @track positions = [];
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

            this.approvalQueue = (data.approvalQueue || []).map(item => ({
                ...item,
                initials: this.getInitials(item.name)
            }));

            this.topCandidates = (data.topCandidates || []).map(c => ({
                ...c,
                initials: this.getInitials(c.name)
            }));

            this.positions = data.positions || [];
            this.alerts = data.alerts || [];
            this.error = undefined;

        } else if (error) {
            this.error = error;
            this.stats = {};
            this.approvalQueue = [];
            this.topCandidates = [];
            this.positions = [];
            this.alerts = [];
        }

        this.isLoading = false;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredDashboardResult)
            .finally(() => { this.isLoading = false; });
    }

    handleViewApprovals() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
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

    handleViewPositions() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Job_Position__c',
                actionName: 'list'
            }
        });
    }
}