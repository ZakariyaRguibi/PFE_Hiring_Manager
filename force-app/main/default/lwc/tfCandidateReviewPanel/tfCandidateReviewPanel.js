import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import emptyStateMountain from '@salesforce/resourceUrl/talentforceLogoMn';
import getCandidatesForStage from '@salesforce/apex/CandidateReviewController.getCandidatesForStage';
import getHiredReviewData from '@salesforce/apex/CandidateReviewController.getHiredReviewData';
import promoteCandidate from '@salesforce/apex/CandidateReviewController.promoteCandidate';
import getUndoImpact from '@salesforce/apex/CandidateReviewController.getUndoImpact';
import undoPromotion from '@salesforce/apex/CandidateReviewController.undoPromotion';
import rejectCandidate from '@salesforce/apex/CandidateReviewController.rejectCandidate';
import markInvitationSent from '@salesforce/apex/CandidateReviewController.markInvitationSent';
import getOfferCapacityWarning from '@salesforce/apex/CandidateReviewController.getOfferCapacityWarning';
import getAcceptCapacityWarning from '@salesforce/apex/CandidateReviewController.getAcceptCapacityWarning';
import extendOffer from '@salesforce/apex/CandidateReviewController.extendOffer';
import markOfferAcceptedWithCapacityDecision from '@salesforce/apex/CandidateReviewController.markOfferAcceptedWithCapacityDecision';
import markOfferDeclined from '@salesforce/apex/CandidateReviewController.markOfferDeclined';

const HIRED_SENTINEL = '__HIRED__';

const DEFAULT_PAGE_SIZE = 10;
const WAITING_PAGE_SIZE = 3;

export default class TfCandidateReviewPanel extends NavigationMixin(LightningElement) {
    @api recordId;

    _stageId;
    _stageName;
    stageData;
    isLoading = false;
    error;
    _waitingOffset = 0;
    _waitingCandidates = [];
    isLoadingMore = false;
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

    // Promote without completed interview warning modal
    showPromoteWarningModal = false;
    promoteWarningAppId = null;
    promoteWarningInterviewStatus = null;

    // Pipeline action guidance modal
    showPipelineActionModal = false;
    pipelineActionModalMessage = '';

    // Capacity confirmation modal
    showCapacityModal = false;
    capacityModalMode = null;
    capacityModalAppId = null;
    capacityModalTitle = '';
    capacityModalSubtitle = '';
    capacityModalBody = '';
    capacityModalPrimaryLabel = '';
    capacityDesiredHires = 0;
    capacityFilledPositions = 0;
    capacityOpenPositions = 0;
    isCapacityActionRunning = false;

    // Expanded card toggle
    expandedAppId = null;

    emptyStateImg = emptyStateMountain;

    @api
    get stageId() { return this._stageId; }
    set stageId(value) {
        if (value !== this._stageId) {
            this._stageId = value;
            this._waitingOffset = 0;
            this._waitingCandidates = [];
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
    get hasWaiting() { return (this.stageData?.waitingTotal ?? this._waitingCandidates.length) > 0; }
    get activeCount()  { return this.stageData?.activeCandidates?.length || 0; }
    get waitingCount() { return this.stageData?.waitingTotal ?? this._waitingCandidates.length; }

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
    get enrichedWaiting() { return this._enrichList(this._waitingCandidates, !this.stageData?.isFirstStage); }

    get visibleWaiting() { return this.enrichedWaiting; }

    get hasMoreWaiting() {
        const total = this.stageData?.waitingTotal ?? 0;
        return this._waitingCandidates.length < total;
    }

    get viewAllLabel() {
        const total = this.stageData?.waitingTotal ?? 0;
        const remaining = total - this._waitingCandidates.length;
        return `Load more (${remaining} remaining)`;
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
                this._waitingOffset = 0;
                this._waitingCandidates = [];
                const data = await getCandidatesForStage({
                    jobPositionId: this.recordId,
                    stageId: this._stageId,
                    waitingOffset: 0
                });
                this._waitingCandidates = data?.waitingCandidates || [];
                this.stageData = data;
            }
        } catch (e) {
            this.error = this._errorMessage(e, 'Failed to load candidates.');
        } finally {
            this.isLoading = false;
        }
    }

    get isHiredView() { return this._stageId === HIRED_SENTINEL; }

    get promoteWarningBody() {
        const s = this.promoteWarningInterviewStatus;
        if (s === 'No Interview') {
            return 'No interview has been recorded in Salesforce for this candidate at this stage. If they haven\'t been interviewed yet, consider scheduling one first. If the interview happened outside Salesforce, you can record the details on the application record before promoting.';
        }
        if (s === 'Pending_Scheduling') {
            return 'This candidate\'s interview is pending scheduling. Promoting now means they will advance without a completed interview on record. Consider waiting until the interview is scheduled and completed, or record the outcome manually on the application.';
        }
        if (s === 'Scheduled') {
            return 'This candidate has a scheduled interview that hasn\'t been completed yet. Promoting now will advance them before their interview result is recorded. If the interview has already taken place, record the outcome on the application record first.';
        }
        if (s === 'Cancelled' || s === 'No_Show') {
            return 'This candidate\'s interview was ' + (s === 'No_Show' ? 'marked as a no-show' : 'cancelled') + '. You can still promote them, but consider recording a new interview outcome on the application record to keep the pipeline data accurate.';
        }
        return 'No completed interview was found for this candidate at this stage. You can still promote them, or record the interview details on the application record first.';
    }
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
        const candidate = this._waitingCandidates.find(c => c.applicationId === appId);
        const ivStatus = candidate?.interviewStatus || 'No Interview';

        if (ivStatus !== 'Completed') {
            this.promoteWarningAppId = appId;
            this.promoteWarningInterviewStatus = ivStatus;
            this.showPromoteWarningModal = true;
            return;
        }

        await this._doPromote(appId);
    }

    async handleConfirmPromoteAnyway() {
        const appId = this.promoteWarningAppId;
        this.showPromoteWarningModal = false;
        this.promoteWarningAppId = null;
        this.promoteWarningInterviewStatus = null;
        await this._doPromote(appId);
    }

    handleClosePromoteWarningModal() {
        this.showPromoteWarningModal = false;
        this.promoteWarningAppId = null;
        this.promoteWarningInterviewStatus = null;
    }

    handleRecordInterviewFirst() {
        const appId = this.promoteWarningAppId;
        this.showPromoteWarningModal = false;
        this.promoteWarningAppId = null;
        this.promoteWarningInterviewStatus = null;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: appId,
                objectApiName: 'Job_Application__c',
                actionName: 'view'
            }
        });
    }

    async _doPromote(appId) {
        try {
            await promoteCandidate({ applicationId: appId, stageId: this._stageId });
            this._toast('Promoted', 'Candidate promoted to this stage.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._handleActionError(e, 'Promote failed.');
        }
    }

    async handleExtendOffer(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            const warning = await getOfferCapacityWarning({ applicationId: appId });

            if (warning?.hasWarning) {
                this._openCapacityModal('offer', appId, warning);
                return;
            }

            await extendOffer({ applicationId: appId, offerAnyway: false });
            this._toast('Offer extended', 'Candidate moved to the Hired column.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._handleActionError(e, 'Extending offer failed.');
        }
    }

    async handleAcceptOffer(event) {
        event.stopPropagation();
        const appId = event.currentTarget.dataset.appid;
        try {
            const warning = await getAcceptCapacityWarning({ applicationId: appId });

            if (warning?.hasWarning) {
                this._openCapacityModal('accept', appId, warning);
                return;
            }

            await markOfferAcceptedWithCapacityDecision({ applicationId: appId, acceptAnyway: false });
            this._toast('Hired', 'Offer accepted.', 'success');
            await this.loadCandidates();
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._handleActionError(e, 'Accept failed.');
        }
    }


    _openCapacityModal(mode, appId, warning) {
        const desired = warning?.desiredHires ?? 0;
        const filled = warning?.filledPositions ?? 0;
        const open = warning?.openPositions ?? 0;

        this.capacityModalMode = mode;
        this.capacityModalAppId = appId;
        this.capacityDesiredHires = desired;
        this.capacityFilledPositions = filled;
        this.capacityOpenPositions = open;

        if (mode === 'offer') {
            this.capacityModalTitle = 'Open positions already filled';
            this.capacityModalSubtitle = 'This job has no open positions left.';
            this.capacityModalBody = 'You can cancel this offer, open the Pipeline Actions tab to decide how to handle the remaining pipeline, or intentionally extend the offer anyway.';
            this.capacityModalPrimaryLabel = 'Offer anyway';
        } else {
            this.capacityModalTitle = 'Hiring target reached';
            this.capacityModalSubtitle = 'Accepting this offer may exceed the desired hires.';
            this.capacityModalBody = 'You can cancel this action, open the Pipeline Actions tab to increase desired hires or choose a finalization strategy, or intentionally accept this offer anyway.';
            this.capacityModalPrimaryLabel = 'Accept anyway';
        }

        this.showCapacityModal = true;
    }

    handleCloseCapacityModal() {
        if (this.isCapacityActionRunning) return;
        this.showCapacityModal = false;
        this.capacityModalMode = null;
        this.capacityModalAppId = null;
    }

    async handleConfirmCapacityAction() {
        if (!this.capacityModalAppId || !this.capacityModalMode) return;
        this.isCapacityActionRunning = true;
        try {
            if (this.capacityModalMode === 'offer') {
                await extendOffer({ applicationId: this.capacityModalAppId, offerAnyway: true });
                this._toast('Offer extended', 'Offer extended even though open positions are filled.', 'success');
            } else {
                await markOfferAcceptedWithCapacityDecision({ applicationId: this.capacityModalAppId, acceptAnyway: true });
                this._toast('Hired', 'Offer accepted even though the hiring target is already reached.', 'success');
            }

            this.showCapacityModal = false;
            this.capacityModalMode = null;
            this.capacityModalAppId = null;
            await this.loadCandidates();
            this.dispatchEvent(new RefreshEvent());
            this.dispatchEvent(new CustomEvent('pipelinechanged'));
        } catch (e) {
            this._handleActionError(e, this.capacityModalMode === 'offer' ? 'Extending offer failed.' : 'Accept failed.');
        } finally {
            this.isCapacityActionRunning = false;
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
            this._toast('Error', this._errorMessage(e, 'Decline failed.'), 'error');
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
            this._toast('Error', this._errorMessage(e, 'Failed to mark invitation.'), 'error');
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
            this._toast('Error', this._errorMessage(e, 'Undo failed.'), 'error');
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
            this._toast('Error', this._errorMessage(e, 'Undo failed.'), 'error');
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
            this._toast('Error', this._errorMessage(e, 'Reject failed.'), 'error');
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

    async handleLoadMoreWaiting() {
        if (this.isLoadingMore || !this.hasMoreWaiting) return;
        this.isLoadingMore = true;
        try {
            const nextOffset = this._waitingOffset + WAITING_PAGE_SIZE;
            const data = await getCandidatesForStage({
                jobPositionId: this.recordId,
                stageId: this._stageId,
                waitingOffset: nextOffset
            });
            this._waitingCandidates = [...this._waitingCandidates, ...(data?.waitingCandidates || [])];
            this._waitingOffset = nextOffset;
            // Keep totals in sync without replacing active candidates
            if (this.stageData) {
                this.stageData = { ...this.stageData, waitingTotal: data?.waitingTotal };
            }
        } catch (e) {
            this._toast('Error', this._errorMessage(e, 'Failed to load more candidates.'), 'error');
        } finally {
            this.isLoadingMore = false;
        }
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


    _handleActionError(error, fallback) {
        const message = this._errorMessage(error, fallback);
        if (this._isPipelineActionRequiredError(message)) {
            this.pipelineActionModalMessage = message;
            this.showPipelineActionModal = true;
            return;
        }
        this._toast('Error', message, 'error');
    }

    _isPipelineActionRequiredError(message) {
        const normalized = (message || '').toLowerCase();
        return normalized.includes('hiring target') ||
            normalized.includes('finalization strategy') ||
            normalized.includes('increase desired hires') ||
            normalized.includes('open positions') ||
            normalized.includes('reached its target');
    }

    handleClosePipelineActionModal() {
        this.showPipelineActionModal = false;
        this.pipelineActionModalMessage = '';
    }

    handleGoToPipelineActions() {
        this.showPipelineActionModal = false;
        this.pipelineActionModalMessage = '';
        this.showCapacityModal = false;
        this.capacityModalMode = null;
        this.capacityModalAppId = null;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Job_Position__c',
                actionName: 'view'
            },
            state: {
                c__focus: 'PipelineActions'
            }
        });
    }

    _errorMessage(error, fallback) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).filter(Boolean).join(', ') || fallback;
        }
        if (error?.body?.pageErrors?.length) {
            return error.body.pageErrors.map((item) => item.message).filter(Boolean).join(', ') || fallback;
        }
        if (error?.body?.fieldErrors) {
            const messages = [];
            Object.keys(error.body.fieldErrors).forEach((fieldName) => {
                error.body.fieldErrors[fieldName].forEach((item) => {
                    if (item?.message) {
                        messages.push(item.message);
                    }
                });
            });
            if (messages.length) {
                return messages.join(', ');
            }
        }
        return error?.body?.message || error?.message || fallback;
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}