import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import startBot from "@salesforce/apex/InterviewBotController.startBot";

/**
 * Headless quick-action LWC (actionType=Action). The framework calls
 * `invoke()` when the user clicks the button — recordId is guaranteed
 * set at that moment, no render lifecycle gymnastics required.
 */
export default class StartVexaBot extends LightningElement {
  @api recordId;

  @api async invoke() {
    try {
      const r = await startBot({ interviewId: this.recordId });
      this.toast(
        r.success ? "success" : "error",
        r.success ? "Vexa bot dispatched" : "Vexa bot — error",
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
