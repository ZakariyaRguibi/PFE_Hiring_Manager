import { LightningElement, api } from 'lwc';
import emptyStateMountain from '@salesforce/resourceUrl/talentforceLogoMn';

export default class TfCandidateReviewContainer extends LightningElement {
    @api recordId;

    selectedStageId;
    selectedStageName;
    pipelineHasStages = false;

    emptyStateImg = emptyStateMountain;

    get showSelectStageEmpty() {
        return this.pipelineHasStages && !this.selectedStageId;
    }

    handleStageSelect(event) {
        this.selectedStageId = event.detail.stageId;
        this.selectedStageName = event.detail.stageName;
    }

    handlePipelineLoaded(event) {
        this.pipelineHasStages = !!event.detail?.hasStages;
        if (!this.pipelineHasStages) {
            this.selectedStageId = undefined;
            this.selectedStageName = undefined;
        }
    }

    handlePipelineChanged() {
        this.template.querySelector('c-tf-interview-pipeline').refreshPipeline();
    }
}