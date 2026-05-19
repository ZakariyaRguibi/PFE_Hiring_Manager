import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import emptyStateMountain from '@salesforce/resourceUrl/tfEmptyStateMountain';
import getStages from '@salesforce/apex/InterviewPipelineController.getStages';
import getPipelineOverview from '@salesforce/apex/CandidateReviewController.getPipelineOverview';
import saveStage from '@salesforce/apex/InterviewPipelineController.saveStage';
import deleteStage from '@salesforce/apex/InterviewPipelineController.deleteStage';
import reorderStages from '@salesforce/apex/InterviewPipelineController.reorderStages';
import saveMember from '@salesforce/apex/InterviewPipelineController.saveMember';
import deleteMember from '@salesforce/apex/InterviewPipelineController.deleteMember';

const ROLE_OPTIONS = [
    { label: 'Lead',     value: 'Lead' },
    { label: 'Support',  value: 'Support' },
    { label: 'Observer', value: 'Observer' }
];

export default class TfInterviewPipeline extends LightningElement {
    @api recordId;

    @track stages = [];
    @track pipelineData = [];
    @track expandedIds = new Set();
    @track selectedStageId = null;
    @track showStageModal = false;
    @track showMemberModal = false;
    @track showManageModal = false;
    @track editingStage = {};
    @track editingMember = { stageId: null, Interviewer__c: null, Role__c: '' };

    isLoading = false;
    isSaving = false;
    _wiredResult;
    _refreshHandler;
    _dragSourceId = null;
    _returnToManage = false;

    roleOptions = ROLE_OPTIONS;
    emptyStateImg = emptyStateMountain;

    @api
    refreshPipeline() {
        refreshApex(this._wiredResult);
        this.loadPipelineOverview();
    }

    // ── Lifecycle ──────────────────────────────────────────────

    connectedCallback() {
        this._refreshHandler = registerRefreshHandler(this, () => {
            refreshApex(this._wiredResult);
            this.loadPipelineOverview();
        });
        this.loadPipelineOverview();
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this._refreshHandler);
    }

    // ── Wire (stages for manage modal) ────────────────────────

    @wire(getStages, { jobPositionId: '$recordId' })
    wiredStages(result) {
        this._wiredResult = result;
        if (result.data) {
            this.stages = result.data.map(w => ({ ...w }));
        }
    }

    // ── Pipeline overview (imperative) ────────────────────────

    async loadPipelineOverview() {
        if (!this.recordId) return;
        this.isLoading = true;
        try {
            this.pipelineData = await getPipelineOverview({ jobPositionId: this.recordId });
            const realStages = this.pipelineData.filter(o => !o.isHired);
            const hasStages = realStages.length > 0;
            // If stages disappeared (e.g. all deleted), clear any prior selection
            if (!hasStages) {
                this.selectedStageId = null;
            }
            // Auto-select first real stage (skip synthetic Hired column)
            if (hasStages && !this.selectedStageId) {
                const firstReal = realStages[0];
                this.selectedStageId = firstReal.stageId;
                Promise.resolve().then(() => {
                    this._fireStageSelect(firstReal);
                });
            }
            this.dispatchEvent(new CustomEvent('pipelineloaded', {
                detail: { hasStages }
            }));
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to load pipeline.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Getters ───────────────────────────────────────────────

    get hasStages() { return this.pipelineData && this.pipelineData.length > 0; }

    get pathSteps() {
        return this.pipelineData.map(ov => {
            const isHired = !!ov.isHired;
            const isSelected = this.selectedStageId === ov.stageId;
            const hasApps = ov.activeCount > 0;
            let cls = 'slds-path__item';
            if (isHired) cls += ' slds-is-won path-hired';
            else if (isSelected) cls += ' slds-is-current slds-is-active';
            else if (hasApps) cls += ' slds-is-complete';
            else cls += ' slds-is-incomplete';
            return {
                key: ov.stageId || '__HIRED__',
                stageId: ov.stageId,
                stageName: ov.stageName,
                countLabel: ov.activeCount > 0 ? String(ov.activeCount) : '',
                pathClass: cls,
                isHired
            };
        });
    }

    get enrichedStages() {
        return this.pipelineData.map(ov => {
            const isHired = !!ov.isHired;
            const enrichedCandidates = (ov.topCandidates || []).map(c => ({
                ...c,
                dateLabel: c.applicationDate ? this._relativeDate(c.applicationDate) : null,
                stageBadgeClass: this._stageBadgeClass(c.applicationStage),
                hasStageBadge: !!c.applicationStage
            }));
            return {
                ...ov,
                topCandidates: enrichedCandidates,
                stage: { Id: ov.stageId || '__HIRED__', Name: ov.stageName, Stage_Number__c: ov.stageNumber },
                countLabel: String(ov.activeCount),
                countBadgeClass: isHired
                    ? (ov.activeCount > 0 ? 'count-badge-hired' : 'count-badge-empty')
                    : (ov.activeCount > 0 ? 'count-badge-active' : 'count-badge-empty'),
                hasCandidates: enrichedCandidates.length > 0,
                hasMore: ov.activeCount > 3,
                isHired,
                columnClass: 'stage-col'
                    + (isHired ? ' stage-col-hired' : '')
                    + (this.selectedStageId === ov.stageId ? ' stage-col-selected' : '')
            };
        });
    }

    _stageBadgeClass(stage) {
        if (stage === 'Hired') return 'stage-badge stage-badge--hired';
        if (stage === 'Offer') return 'stage-badge stage-badge--offer';
        return null;
    }

    // Manage modal getters
    get modalTitle() { return this.editingStage.Id ? 'Edit Stage' : 'New Stage'; }
    get saveLabel() { return this.isSaving ? 'Saving...' : 'Save'; }

    get totalWeight() {
        return this.stages.reduce((sum, w) => sum + (Number(w.stage.Stage_Weight__c) || 0), 0);
    }

    get weightTotalClass() {
        return this.totalWeight === 100
            ? 'slds-text-body_small slds-text-color_success'
            : 'slds-text-body_small slds-text-color_error';
    }

    get weightBarValue() {
        return Math.min(this.totalWeight, 100);
    }

    get managedStages() {
        return this.stages.map(w => {
            const s = w.stage;
            const members = (w.members || []).map(m => ({
                ...m,
                initials: this._initials(m.Interviewer__r?.Name)
            }));
            const AVATAR_COLORS = ['avatar-color-1','avatar-color-2','avatar-color-3','avatar-color-4','avatar-color-5','avatar-color-6'];
            const coloredMembers = members.map((m, i) => ({
                ...m,
                avatarClass: `interviewer-avatar ${AVATAR_COLORS[i % AVATAR_COLORS.length]}`
            }));
            const visibleMembers = coloredMembers.slice(0, 3);
            const overflowCount = coloredMembers.length > 3 ? coloredMembers.length - 3 : 0;
            return {
                stage: s,
                members: coloredMembers,
                hasMembers: coloredMembers.length > 0,
                visibleMembers,
                overflowCount,
                expanded: this.expandedIds.has(s.Id),
                dateLabel: this._dateLabel(s.Start_Date__c, s.End_Date__c),
                durationLabel: s.Duration_Minutes__c != null ? `${s.Duration_Minutes__c} min`  : null,
                weightLabel:   s.Stage_Weight__c   != null ? `Weight: ${s.Stage_Weight__c}%` : null,
                maxScoreLabel: s.Max_Score__c       != null ? `Max: ${s.Max_Score__c}`        : null,
                passLabel:     s.Passing_Threshold__c != null ? `Pass: ${s.Passing_Threshold__c}` : null
            };
        });
    }

    // ── Stage selection ───────────────────────────────────────

    handleStageClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        if (this.selectedStageId === id) return;
        this.selectedStageId = id;
        if (id === '__HIRED__') {
            const hiredOv = this.pipelineData.find(o => o.isHired);
            this.dispatchEvent(new CustomEvent('stageselect', {
                detail: { stageId: '__HIRED__', stageName: hiredOv?.stageName || 'Hired', stageNumber: null }
            }));
            return;
        }
        const ov = this.pipelineData.find(o => o.stageId === id);
        if (ov) this._fireStageSelect(ov);
    }

    handleViewAll(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        if (!id || id === '__HIRED__') return;
        this.selectedStageId = id;
        const ov = this.pipelineData.find(o => o.stageId === id);
        if (ov) this._fireStageSelect(ov);
    }

    _fireStageSelect(ov) {
        this.dispatchEvent(new CustomEvent('stageselect', {
            detail: { stageId: ov.stageId, stageName: ov.stageName, stageNumber: ov.stageNumber }
        }));
    }

    // ── Manage Stages Modal ───────────────────────────────────

    handleOpenManageStages() {
        this.showManageModal = true;
    }

    handleCloseManageModal() {
        this.showManageModal = false;
    }

    // ── Stage CRUD ────────────────────────────────────────────

    handleAddStage() {
        this.editingStage = {};
        this._stashManageModal();
        this.showStageModal = true;
    }

    handleEditStage(event) {
        const id = event.currentTarget.dataset.id;
        const wrapper = this.stages.find(w => w.stage.Id === id);
        this.editingStage = { ...wrapper.stage };
        this._stashManageModal();
        this.showStageModal = true;
    }

    handleStageFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editingStage = { ...this.editingStage, [field]: event.detail.value };
    }

    async handleSaveStage() {
        const inputs = this.template.querySelectorAll('lightning-input');
        const valid = [...inputs].reduce((acc, i) => i.reportValidity() && acc, true);
        if (!valid) return;
        if (!this.editingStage.Duration_Minutes__c) {
            this.editingStage = { ...this.editingStage, Duration_Minutes__c: 60 };
        }

        this.isSaving = true;
        try {
            await saveStage({ stage: this.editingStage, jobPositionId: this.recordId });
            await refreshApex(this._wiredResult);
            await this.loadPipelineOverview();
            this.showStageModal = false;
            this._popManageModal();
            this._toast('Success', 'Stage saved.', 'success');
        } catch (e) {
            this._toast('Error', e.body?.message || 'Save failed.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteStage(event) {
        const id = event.currentTarget.dataset.id;
        if (!confirm('Delete this stage? This cannot be undone.')) return;
        try {
            await deleteStage({ stageId: id });
            this.expandedIds.delete(id);
            await refreshApex(this._wiredResult);
            await this.loadPipelineOverview();
            this._toast('Deleted', 'Stage removed.', 'success');
        } catch (e) {
            this._toast('Error', e.body?.message || 'Delete failed.', 'error');
        }
    }

    handleCloseModal() {
        this.showStageModal = false;
        this._popManageModal();
    }

    // ── Toggle expand (manage modal) ──────────────────────────

    handleToggleExpand(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.expandedIds);
        next.has(id) ? next.delete(id) : next.add(id);
        this.expandedIds = next;
    }

    // ── Drag & Drop reorder (manage modal) ────────────────────

    handleDragStart(event) {
        this._dragSourceId = event.currentTarget.dataset.id;
        event.currentTarget.classList.add('stage-dragging');
        event.dataTransfer.effectAllowed = 'move';
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        event.currentTarget.classList.add('stage-drag-over');
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('stage-drag-over');
    }

    async handleDrop(event) {
        event.preventDefault();
        const targetId = event.currentTarget.dataset.id;
        event.currentTarget.classList.remove('stage-drag-over');
        if (!targetId || this._dragSourceId === targetId) return;

        const ids = this.stages.map(w => w.stage.Id);
        const fromIdx = ids.indexOf(this._dragSourceId);
        const toIdx = ids.indexOf(targetId);
        if (fromIdx === -1 || toIdx === -1) return;

        const reordered = [...this.stages];
        const [moved] = reordered.splice(fromIdx, 1);
        reordered.splice(toIdx, 0, moved);
        this.stages = reordered;

        try {
            await reorderStages({ orderedIds: reordered.map(w => w.stage.Id) });
            await refreshApex(this._wiredResult);
            await this.loadPipelineOverview();
        } catch (e) {
            this._toast('Error', 'Reorder failed.', 'error');
            await refreshApex(this._wiredResult);
        }
    }

    handleDragEnd(event) {
        event.currentTarget.classList.remove('stage-dragging');
        this.template.querySelectorAll('.stage-drag-over').forEach(el => el.classList.remove('stage-drag-over'));
        this._dragSourceId = null;
    }

    // ── Member CRUD ───────────────────────────────────────────

    handleAddMember(event) {
        this.editingMember = { stageId: event.currentTarget.dataset.stageid, Interviewer__c: null, Role__c: '' };
        this._stashManageModal();
        this.showMemberModal = true;
    }

    handleInterviewerChange(event) {
        this.editingMember = { ...this.editingMember, Interviewer__c: event.detail.recordId };
    }

    handleMemberRoleChange(event) {
        this.editingMember = { ...this.editingMember, Role__c: event.detail.value };
    }

    async handleSaveMember() {
        if (!this.editingMember.Interviewer__c) {
            this._toast('Validation', 'Please select an interviewer.', 'warning');
            return;
        }
        if (!this.editingMember.Role__c) {
            this._toast('Validation', 'Role is required.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            const memberRecord = {
                Interview_Stage__c: this.editingMember.stageId,
                Interviewer__c:     this.editingMember.Interviewer__c,
                Role__c:            this.editingMember.Role__c
            };
            await saveMember({ member: memberRecord });
            await refreshApex(this._wiredResult);
            this.showMemberModal = false;
            this._popManageModal();
            this._toast('Success', 'Interviewer added.', 'success');
        } catch (e) {
            this._toast('Error', e.body?.message || 'Save failed.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteMember(event) {
        const memberId = event.currentTarget.dataset.memberid;
        try {
            await deleteMember({ memberId });
            await refreshApex(this._wiredResult);
            this._toast('Removed', 'Interviewer removed.', 'success');
        } catch (e) {
            this._toast('Error', e.body?.message || 'Delete failed.', 'error');
        }
    }

    handleCloseMemberModal() {
        this.showMemberModal = false;
        this._popManageModal();
    }

    // ── Manage-modal stash/pop (avoid modal-on-modal) ─────────

    _stashManageModal() {
        if (this.showManageModal) {
            this._returnToManage = true;
            this.showManageModal = false;
        }
    }

    _popManageModal() {
        if (this._returnToManage) {
            this._returnToManage = false;
            this.showManageModal = true;
        }
    }

    // ── Utilities ─────────────────────────────────────────────

    _initials(name) {
        if (!name) return '?';
        return name.split(' ').map(n => n[0]).slice(0, 2).join('').toUpperCase();
    }

    _dateLabel(start, end) {
        if (!start && !end) return null;
        const fmt = d => new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        if (start && end) return `${fmt(start)} – ${fmt(end)}`;
        if (start) return `From ${fmt(start)}`;
        return `Until ${fmt(end)}`;
    }

    _relativeDate(dateStr) {
        const d = new Date(dateStr);
        const now = new Date();
        const diffDays = Math.floor((now - d) / (1000 * 60 * 60 * 24));
        if (diffDays === 0) return 'Applied today';
        if (diffDays === 1) return 'Applied 1 day ago';
        if (diffDays < 30) return `Applied ${diffDays} days ago`;
        return `Applied ${d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`;
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}