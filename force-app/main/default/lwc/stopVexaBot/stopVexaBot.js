import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import stopBot from "@salesforce/apex/InterviewBotController.stopBot";

export default class StopVexaBot extends LightningElement {
  @api recordId;

  @api async invoke() {
    try {
      const r = await stopBot({ interviewId: this.recordId });
      this.toast(
        r.success ? "success" : "error",
        r.success ? "Vexa bot stopped" : "Vexa bot — error",
        r.message
      );
      if (r.success) getRecordNotifyChange([{ recordId: this.recordId }]);
    } catch (e) {
      this.toast("error", "Vexa bot — error", e?.body?.message ?? String(e));
    }
  }

  toast(variant, title, message) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
