import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import emptyStateMountain from '@salesforce/resourceUrl/tfEmptyStateMountain';
import getCandidatesForStage from '@salesforce/apex/CandidateReviewController.getCandidatesForStage';
import getHiredReviewData from '@salesforce/apex/CandidateReviewController.getHiredReviewData';
import promoteCandidate from '@salesforce/apex/CandidateReviewController.promoteCandidate';
import getUndoImpact from '@salesforce/apex/CandidateReviewController.getUndoImpact';
import undoPromotion from '@salesforce/apex/CandidateReviewController.undoPromotion';
import rejectCandidate from '@salesforce/apex/CandidateReviewController.rejectCandidate';
import markInvitationSent from '@salesforce/apex/CandidateReviewController.markInvitationSent';
import extendOffer from '@salesforce/apex/CandidateReviewController.extendOffer';
import markOfferAccepted from '@salesforce/apex/CandidateReviewController.markOfferAccepted';
import markOfferDeclined from '@salesforce/apex/CandidateReviewController.markOfferDeclined';

const HIRED_SENTINEL = '__HIRED__';

const DEFAULT_PAGE_SIZE = 10;

export default class TfCandidateReviewPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    _stageId;
    _stageName;
    stageData;
    isLoading = false;
    error;
    showAllWaiting = false;
    activeTab = 'active';

    // Reject modal
    showRejectModal = false;
    rejectAppId = null;
    rejectReason = '';

    // Undo modal
    showUndoModal = false;
    undoAppId = null;
    undoReason = '';
    undoImpact = null;
    undoFormattedDate = null;
    isUndoing = false;

    // Expanded card toggle
    expandedAppId = null;

    emptyStateImg = emptyStateMountain;

    @api
    get stageId() { return this._stageId; }
    set stageId(value) {
        if (value !== this._stageId) {
            this._stageId = value;
            this.showAllWaiting = false;
            this.activeTab = 'active';
            this.expandedAppId = null;
            this.loadCandidates();
        }
    }

    @api
    get stageName() { return this._stageName; }
    set stageName(value) { this._stageName = value; }

    // ── Getters ─────────────────────────────────────────────────────────

    get isActiveTab()  { return this.activeTab === 'active'; }
    get isWaitingTab() { return this.activeTab === 'waiting'; }

    get activeTabClass() {
        return 'slds-tabs_default__item' + (this.isActiveTab ? ' slds-is-active' : '');
    }
    get waitingTabClass() {
        return 'slds-tabs_default__item' + (this.isWaitingTab ? ' slds-is-active' : '');
    }

    get hasActive()  { return this.stageData?.activeCandidates?.length > 0; }
    get hasWaiting() { return this.stageData?.waitingCandidates?.length > 0; }
    get activeCount()  { return this.stageData?.activeCandidates?.length || 0; }
    get waitingCount() { return this.stageData?.waitingCandidates?.length || 0; }

    get activeTabLabel()  {
        return this.isHiredView ? `Offered & Hired (${this.activeCount})` : `Active (${this.activeCount})`;
    }
    get waitingTabLabel() {
        return this.isHiredView ? `Ready for Offer (${this.waitingCount})` : `Waiting List (${this.waitingCount})`;
    }
    get waitingScoreLabel() { return this.stageData?.isFirstStage ? 'AI Score' : 'Prev. Score'; }
    get allStages() { return this.stageData?.allStages || []; }

    get enrichedActive() {
        const sorted = [...(this.stageData?.activeCandidates || [])].sort((a, b) =>
            (b.interviewScore ?? -1) - (a.interviewScore ?? -1)
        );
        return this._enrichList(sorted, true);
    }
    get enrichedWaiting() { return this._enrichList(this.stageData?.waitingCandidates || [], !this.stageData?.isFirstStage); }

    get visibleWaiting() {
        if (this.showAllWaiting) return this.enrichedWaiting;
        return this.enrichedWaiting.slice(0, DEFAULT_PAGE_SIZE);
    }

    get hasMoreWaiting() {
        return this.enrichedWaiting.length > DEFAULT_PAGE_SIZE;
    }

    get viewAllLabel() {
        return this.showAllWaiting
            ? 'Show less'
            : `View all ${this.enrichedWaiting.length} candidates`;
    }

    // ── Data loading ────────────────────────────────────────────────────

    async loadCandidates() {
        if (!this._stageId || !this.recordId) return;
        this.isLoading = true;
        this.error = null;
        try {
            if (this._stageId === HIRED_SENTINEL) {
                this.stageData = await getHiredReviewData({ jobPositionId: this.recordId });
            } else {
                this.stageData = await getCandidatesForStage({
                    jobPositionId: this.recordId,
                    stageId: this._stageId
                });
            }
        } catch (e) {
            this.error = e.body?.message || 'Failed to load candidates.';
        } finally {
            this.isLoading = false;
        }
    }

    get isHiredView() { return this._stageId === HIRED_SENTINEL; }
    get activeStatusColumnLabel() { return this.isHiredView ? 'Status' : 'Recommendation'; }
    get waitingPromoteLabel() { return this.isHiredView ? 'Offer' : 'Promote'; }
    get waitingPromoteVariant() { return this.isHiredView ? 'success' : 'brand'; }

    // ── Empty state copy ───────────────────────────────────────────────
    get emptyActiveTitle() {
        return this.isHiredView ? 'No offers extended yet' : 'No candidates in this stage';
    }
    get emptyActiveText() {
        return this.isHiredView
            ? 'Once you extend an offer from the Ready for Offer list, the candidate will appear here.'
            : 'Promote a candidate from the Waiting List tab to start reviewing them here.';
    }
    get emptyWaitingTitle() {
        if (this.isHiredView) return 'Nobody is ready for an offer';
        if (this.stageData?.isFirstStage) return 'No new applications';
        return 'Waiting list is empty';
    }
    get emptyWaitingText() {
        if (this.isHiredView) return 'Candidates who clear the final interview stage will show up here, ready for an offer.';
        if (this.stageData?.isFirstStage) return 'New applications matching this position will appear here automatically.';
        return 'Every candidate from the previous stage has been processed.';
    }

    // ── Actions ─────────────────────────────────────────────────────────

    handleActionStopProp(event) {
        event.stopPropagation();
    }

    async handlePromote(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            await promoteCandidate({ applicationId: appId, stageId: this._stageId });
            this._toast('Promoted', 'Candidate promoted to this stage.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Promote failed.', 'error');
        }
    }

    async handleExtendOffer(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            await extendOffer({ applicationId: appId });
            this._toast('Offer extended', 'Candidate moved to the Hired column.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Extending offer failed.', 'error');
        }
    }

    async handleAcceptOffer(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            await markOfferAccepted({ applicationId: appId });
            this._toast('Hired', 'Offer accepted.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Accept failed.', 'error');
        }
    }

    async handleDeclineOffer(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            await markOfferDeclined({ applicationId: appId });
            this._toast('Declined', 'Candidate marked as withdrawn.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Decline failed.', 'error');
        }
    }

    async handleInvite(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            await markInvitationSent({ applicationId: appId, stageId: this._stageId });
            this._toast('Invited', 'Candidate has been marked as invited.', 'success');
            await this.loadCandidates();
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to mark invitation.', 'error');
        }
    }

    async handleUndo(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            const impact = await getUndoImpact({ applicationId: appId });
            if (!impact?.requiresConfirmation) {
                await undoPromotion({ applicationId: appId, reason: null });
                this._toast('Undone', 'Promotion reversed.', 'success');
                await this.loadCandidates();
                this.dispatchEvent(new CustomEvent('pipelinechanged'));
                return;
            }
            this.undoAppId = appId;
            this.undoImpact = impact;
            this.undoReason = '';
            this.undoFormattedDate = impact.scheduledDateTime
                ? this._formatScheduledDate(impact.scheduledDateTime)
                : null;
            this.showUndoModal = true;
        } catch (e) {
            this._toast('Error', e.body?.message || 'Undo failed.', 'error');
        }
    }

    handleUndoReasonChange(event) {
        this.undoReason = event.detail.value;
    }

    handleCloseUndoModal() {
        this.showUndoModal = false;
        this.undoAppId = null;
        this.undoImpact = null;
        this.undoReason = '';
        this.undoFormattedDate = null;
    }

    async handleConfirmUndo() {
        if (!this.undoReason || !this.undoReason.trim()) {
            this._toast('Validation', 'A reason is required.', 'warning');
            return;
        }
        this.isUndoing = true;
        try {
            await undoPromotion({ applicationId: this.undoAppId, reason: this.undoReason });
            this._toast('Undone', 'Promotion reversed and interview cancelled.', 'success');
            this.handleCloseUndoModal();
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Undo failed.', 'error');
        } finally {
            this.isUndoing = false;
        }
    }

    _formatScheduledDate(iso) {
        const d = new Date(iso);
        const datePart = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
        const timePart = d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
        return `${datePart} at ${timePart}`;
    }

    handleOpenReject(event) {
        event.stopPropagation();
        this.rejectAppId = event.currentTarget.dataset.appid;
        this.rejectReason = '';
        this.showRejectModal = true;
    }

    handleRejectReasonChange(event) {
        this.rejectReason = event.detail.value;
    }

    handleCloseRejectModal() {
        this.showRejectModal = false;
        this.rejectAppId = null;
    }

    async handleConfirmReject() {
        if (!this.rejectReason || !this.rejectReason.trim()) {
            this._toast('Validation', 'A rejection reason is required.', 'warning');
            return;
        }
        try {
            await rejectCandidate({ applicationId: this.rejectAppId, reason: this.rejectReason });
            this._toast('Rejected', 'Candidate rejected.', 'success');
            this.showRejectModal = false;
            this.rejectAppId = null;
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Reject failed.', 'error');
        }
    }

    handleNavToApp(event) {
        event.preventDefault();
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid || event.detail?.appId;
        if (!appId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: appId, actionName: 'view' }
        });
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this.expandedAppId = null;
    }

    handleToggleViewAll() {
        this.showAllWaiting = !this.showAllWaiting;
    }

    handleRowClick(event) {
        const appId = event.currentTarget.dataset.appid;
        this.expandedAppId = this.expandedAppId === appId ? null : appId;
    }

    @api
    refresh() { return this.loadCandidates(); }

    // ── Private helpers ─────────────────────────────────────────────────

    _enrichList(candidates, interviewScoreOnly = false) {
        return candidates.map((c, idx) => {
            const isRejected = c.selectionStatus === 'Rejected';
            const skillTags  = c.extractedSkills
                ? c.extractedSkills.split(',').map(s => s.trim()).filter(Boolean).slice(0, 6)
                : null;
            const yrs = c.extractedExperience ?? c.yearsOfExperience;
            const experienceLabel = yrs != null ? `${yrs} yrs exp` : 'N/A';
            const educationLabel  = c.extractedEducation || c.educationLevel || 'N/A';
            const hasSubScores = c.skillsScore != null || c.experienceScore != null || c.educationScore != null;
            const isExpanded = this.expandedAppId === c.applicationId;
            const displayScore = interviewScoreOnly ? c.interviewScore : (c.interviewScore ?? c.aiScore);
            const score = displayScore != null ? Math.round(displayScore) : null;

            const ivStatus = c.interviewStatus || 'No Interview';
            let interviewStatusLabel;
            let interviewStatusClass;
            if (ivStatus === 'No Interview') {
                interviewStatusLabel = 'No Interview';
                interviewStatusClass = 'slds-badge';
            } else if (ivStatus === 'Pending_Scheduling') {
                interviewStatusLabel = 'Pending Scheduling';
                interviewStatusClass = 'slds-badge slds-theme_warning';
            } else if (ivStatus === 'Scheduled') {
                if (c.scheduledDateTime) {
                    const d = new Date(c.scheduledDateTime);
                    const isPast = d < new Date();
                    interviewStatusLabel = (isPast ? 'Past · ' : '')
                        + d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
                        + ' ' + d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
                    interviewStatusClass = isPast ? 'slds-badge slds-theme_error' : 'slds-badge slds-theme_info';
                } else {
                    interviewStatusLabel = 'Scheduled';
                    interviewStatusClass = 'slds-badge slds-theme_info';
                }
            } else if (ivStatus === 'Completed') {
                const threshold = this.stageData?.passingThreshold;
                if (score != null && threshold != null) {
                    if (score >= threshold) {
                        interviewStatusLabel = 'Passed';
                        interviewStatusClass = 'slds-badge slds-theme_success';
                    } else {
                        interviewStatusLabel = 'Below Threshold';
                        interviewStatusClass = 'slds-badge slds-theme_error';
                    }
                } else {
                    interviewStatusLabel = 'Completed';
                    interviewStatusClass = 'slds-badge';
                }
            } else if (ivStatus === 'Cancelled') {
                interviewStatusLabel = 'Cancelled';
                interviewStatusClass = 'slds-badge';
            } else if (ivStatus === 'No_Show') {
                interviewStatusLabel = 'No Show';
                interviewStatusClass = 'slds-badge';
            } else {
                interviewStatusLabel = ivStatus;
                interviewStatusClass = 'slds-badge';
            }

            return {
                ...c,
                rank: idx + 1,
                scoreLabel: score != null ? String(score) : null,
                scoreBadgeClass: this._scoreBadgeClass(displayScore),
                interviewStatusLabel,
                interviewStatusClass,
                isRejected,
                formattedDate: c.applicationDate || 'N/A',
                skillTags, experienceLabel, educationLabel, hasSubScores,
                isExpanded,
                expandedRowKey: c.applicationId + '-detail',
                invitationSent: c.invitationSent === true,
                rowClass: 'slds-hint-parent clickable-row' + (isExpanded ? ' row-expanded' : ''),
                skillsScoreLabel: c.skillsScore != null ? String(Math.round(c.skillsScore)) : '--',
                expScoreLabel:    c.experienceScore != null ? String(Math.round(c.experienceScore)) : '--',
                eduScoreLabel:    c.educationScore != null ? String(Math.round(c.educationScore)) : '--',
                skillsPercent: Math.min(c.skillsScore || 0, 100),
                expPercent:    Math.min(c.experienceScore || 0, 100),
                eduPercent:    Math.min(c.educationScore || 0, 100),
                recommendation: this._currentStageRecommendation(c),
                recommendationClass: this._recommendationClass(this._currentStageRecommendation(c)),
                isOffer: c.applicationStage === 'Offer',
                isHired: c.applicationStage === 'Hired',
                stageBadgeLabel: c.applicationStage,
                stageBadgeClass: this._appStageBadgeClass(c.applicationStage)
            };
        });
    }

    _appStageBadgeClass(stage) {
        if (stage === 'Hired') return 'slds-badge slds-theme_success';
        if (stage === 'Offer') return 'slds-badge slds-theme_warning';
        return 'slds-badge';
    }

    _currentStageRecommendation(c) {
        const stageName = this.allStages.find(s => s.stageId === c.currentStageId)?.stageName;
        if (!stageName) return null;
        const review = (c.interviewerReviews || []).find(r => r.stageName === stageName && r.recommendation);
        return review?.recommendation ?? null;
    }

    _recommendationClass(rec) {
        if (!rec) return null;
        return 'rec-badge rec-' + rec.toLowerCase().replace(/\s+/g, '-');
    }

    _scoreBadgeClass(score) {
        if (score == null) return 'score-badge score-badge--none';
        if (score >= 80)   return 'score-badge score-badge--high';
        if (score >= 60)   return 'score-badge score-badge--medium';
        return 'score-badge score-badge--low';
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}