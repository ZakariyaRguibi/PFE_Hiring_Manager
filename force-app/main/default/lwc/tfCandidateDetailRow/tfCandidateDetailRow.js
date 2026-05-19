import { LightningElement, api } from 'lwc';

export default class TfCandidateDetailRow extends LightningElement {
    @api candidate;
    @api allStages = [];

    // ── Candidate info ──────────────────────────────────────────────────

    get hasSkills() {
        return this.candidate?.skillTags?.length > 0;
    }

    get hasSubScores() {
        return this.candidate?.hasSubScores;
    }

    // ── Stage progress timeline ─────────────────────────────────────────

    get hasStageProgress() {
        return this.allStages?.length > 0;
    }

    get stageProgressItems() {
        if (!this.allStages?.length) return [];
        const currentStageId = this.candidate?.currentStageId;
        const currentStage = this.allStages.find(s => s.stageId === currentStageId);
        const currentNum = currentStage?.stageNumber ?? null;
        return this.allStages.map(s => {
            const isDone     = currentNum != null && s.stageNumber < currentNum;
            const isCurrent  = s.stageId === currentStageId;
            let stepClass = 'stage-step';
            if (isDone)    stepClass += ' stage-step--done';
            else if (isCurrent) stepClass += ' stage-step--current';
            else           stepClass += ' stage-step--upcoming';
            return { ...s, key: s.stageId, isDone, isCurrent, stepClass };
        });
    }

    // ── Interviewer reviews ─────────────────────────────────────────────

    get hasInterviewerReviews() {
        return this.candidate?.interviewerReviews?.length > 0;
    }

    get reviewsByStage() {
        const reviews = this.candidate?.interviewerReviews || [];
        const groups = new Map();
        for (const r of reviews) {
            const stageName = r.stageName || 'Unknown Stage';
            if (!groups.has(stageName)) {
                groups.set(stageName, { key: stageName, stageName, reviews: [] });
            }
            groups.get(stageName).reviews.push({
                ...r,
                key: stageName + '-' + r.interviewerName + (r.score ?? ''),
                scoreDisplay: r.score != null ? String(Math.round(r.score)) : null,
                scoreBadgeClass: this._scoreBadgeClass(r.score),
                recommendationClass: this._recommendationClass(r.recommendation),
                hasNotes: !!r.notes
            });
        }
        return [...groups.values()];
    }

    _scoreBadgeClass(score) {
        if (score == null) return 'score-badge score-badge--none';
        if (score >= 80)   return 'score-badge score-badge--high';
        if (score >= 60)   return 'score-badge score-badge--medium';
        return 'score-badge score-badge--low';
    }

    _recommendationClass(rec) {
        if (!rec) return 'rec-badge';
        return 'rec-badge rec-' + rec.toLowerCase().replace(/\s+/g, '-');
    }

    handleViewRecord() {
        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { appId: this.candidate.applicationId }
        }));
    }
}