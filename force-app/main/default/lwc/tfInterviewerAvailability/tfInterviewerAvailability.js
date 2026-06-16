import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMyWindows from "@salesforce/apex/InterviewerAvailabilityController.getMyWindows";
import getMyScheduledInterviews from "@salesforce/apex/InterviewerAvailabilityController.getMyScheduledInterviews";
import saveWindow from "@salesforce/apex/InterviewerAvailabilityController.saveWindow";
import deleteWindow from "@salesforce/apex/InterviewerAvailabilityController.deleteWindow";
import toggleWindowBlock from "@salesforce/apex/InterviewerAvailabilityController.toggleWindowBlock";

const DAY_OPTIONS = [
  { label: "Monday", value: "Monday" },
  { label: "Tuesday", value: "Tuesday" },
  { label: "Wednesday", value: "Wednesday" },
  { label: "Thursday", value: "Thursday" },
  { label: "Friday", value: "Friday" },
  { label: "Saturday", value: "Saturday" },
  { label: "Sunday", value: "Sunday" }
];

const DAY_ORDER = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday"
];
const DAY_SHORT = {
  Monday: "Mon",
  Tuesday: "Tue",
  Wednesday: "Wed",
  Thursday: "Thu",
  Friday: "Fri",
  Saturday: "Sat",
  Sunday: "Sun"
};

const START_HOUR = 7;
const END_HOUR = 23;
const TOTAL_HOURS = END_HOUR - START_HOUR; // 16
const SNAP_MINUTES = 30;

export default class TfInterviewerAvailability extends LightningElement {
  @track windows = [];
  @track interviews = [];
  @track showModal = false;
  @track newWindow = {
    Day_Of_Week__c: "Monday",
    startTime: "08:00",
    endTime: "12:00",
    isRecurring: true
  };

  // Week navigation
  @track _weekStart = null; // Date string YYYY-MM-DD (Monday)

  // Drag state
  @track _dragDay = null;
  @track _dragStartFrac = null;
  @track _dragCurrentFrac = null;

  isSaving = false;
  @track isLoading = false;
  @track openMenuId = null;
  @track menuPos = { top: 0, right: 0 };
  dayOptions = DAY_OPTIONS;

  // ── Lifecycle ───────────────────────────────────────────────────────────

  connectedCallback() {
    this._weekStart = this._currentMonday();
    this._loadData();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  async _loadData() {
    this.isLoading = true;
    this.windows = [];
    this.interviews = [];
    await Promise.all([this._loadWindows(), this._loadInterviews()]);
    this.isLoading = false;
  }

  async _loadWindows() {
    try {
      const data = await getMyWindows({ weekStart: this._weekStart });
      this.windows = (data || []).map((w) => this._enrichWindow(w));
    } catch (e) {
      this._toast(
        "Error",
        e.body?.message || "Failed to load windows.",
        "error"
      );
      this.windows = [];
    }
  }

  async _loadInterviews() {
    try {
      const data = await getMyScheduledInterviews({
        weekStart: this._weekStart
      });
      this.interviews = (data || []).map((iv) => this._enrichInterview(iv));
    } catch (e) {
      this._toast(
        "Error",
        e.body?.message || "Failed to load scheduled interviews.",
        "error"
      );
      this.interviews = [];
    }
  }

  // ── Week navigation ────────────────────────────────────────────────────

  get weekLabel() {
    if (!this._weekStart) return "";
    const mon = this._parseDate(this._weekStart);
    const sun = new Date(mon);
    sun.setDate(sun.getDate() + 6);
    const opts = { month: "short", day: "numeric" };
    const monLabel = mon.toLocaleDateString("en-US", opts);
    const sunLabel = sun.toLocaleDateString("en-US", {
      ...opts,
      year: "numeric"
    });
    return `${monLabel} – ${sunLabel}`;
  }

  get isCurrentWeek() {
    return this._weekStart === this._currentMonday();
  }

  get isPastWeek() {
    return this._weekStart < this._currentMonday();
  }

  _isDayPast(dayName) {
    const idx = DAY_ORDER.indexOf(dayName);
    const dayDate = this._parseDate(this._weekStart);
    dayDate.setDate(dayDate.getDate() + idx);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    return dayDate < today;
  }

  handlePrevWeek() {
    const d = this._parseDate(this._weekStart);
    d.setDate(d.getDate() - 7);
    this._weekStart = this._formatDate(d);
    this._loadData();
  }

  handleNextWeek() {
    const d = this._parseDate(this._weekStart);
    d.setDate(d.getDate() + 7);
    this._weekStart = this._formatDate(d);
    this._loadData();
  }

  handleToday() {
    this._weekStart = this._currentMonday();
    this._loadData();
  }

  // ── Getters ─────────────────────────────────────────────────────────────

  get saveLabel() {
    return this.isSaving ? "Saving..." : "Save";
  }
  get modalClass() {
    return this.showModal ? "" : "slds-hide";
  }

  get timeLabels() {
    const labels = [];
    for (let h = START_HOUR; h <= END_HOUR; h++) {
      const pct = ((h - START_HOUR) / TOTAL_HOURS) * 100;
      labels.push({
        label: h + ":00",
        style: `left:${pct}%`,
        lineStyle: `left:${pct}%`
      });
    }
    return labels;
  }

  get calendarRows() {
    const todayStr = this._formatDate(new Date());
    return DAY_ORDER.map((day, idx) => {
      const dayDate = this._parseDate(this._weekStart);
      dayDate.setDate(dayDate.getDate() + idx);
      const isPast = this._formatDate(dayDate) < todayStr;
      const dateNum = dayDate.getDate();

      const isDragging =
        this._dragDay === day &&
        this._dragStartFrac !== null &&
        this._dragCurrentFrac !== null;
      let ghostStyle = "";
      let ghostLabel = "";
      if (isDragging) {
        const lo = Math.min(this._dragStartFrac, this._dragCurrentFrac);
        const hi = Math.max(this._dragStartFrac, this._dragCurrentFrac);
        ghostStyle = `left:${lo}%;width:${hi - lo}%`;
        ghostLabel = `${this._fracToLabel(lo)} – ${this._fracToLabel(hi)}`;
      }
      return {
        day,
        shortLabel: `${DAY_SHORT[day]} ${dateNum}`,
        isPast,
        isEditable: !isPast,
        trackClass: isPast
          ? "planner__track planner__track--past"
          : "planner__track",
        dayClass: isPast ? "day-name day-name--past" : "day-name",
        windows: this.windows
          .filter((w) => w.Day_Of_Week__c === day)
          .map((w) => ({ ...w, menuOpen: this.openMenuId === w.Id })),
        interviews: this.interviews.filter((iv) => iv.dayOfWeek === day),
        showGhost: isDragging,
        ghostStyle,
        ghostLabel
      };
    });
  }

  // ── Drag to create ──────────────────────────────────────────────────────

  handleTrackMouseDown(event) {
    if (this._isDayPast(event.currentTarget.dataset.day)) return;
    if (event.button !== 0) return;
    if (event.target.closest(".time-block")) return;
    const frac = this._snapFrac(this._eventFrac(event));
    this._dragDay = event.currentTarget.dataset.day;
    this._dragStartFrac = frac;
    this._dragCurrentFrac = frac;
    event.preventDefault();
  }

  handleTrackMouseMove(event) {
    if (!this._dragDay || this._dragDay !== event.currentTarget.dataset.day)
      return;
    this._dragCurrentFrac = this._snapFrac(this._eventFrac(event));
  }

  handleTrackMouseUp(event) {
    if (!this._dragDay || this._dragDay !== event.currentTarget.dataset.day)
      return;
    this._commitDrag();
  }

  handleTrackMouseLeave(event) {
    if (!this._dragDay || this._dragDay !== event.currentTarget.dataset.day)
      return;
    this._commitDrag();
  }

  _commitDrag() {
    const day = this._dragDay;
    const lo = Math.min(this._dragStartFrac, this._dragCurrentFrac);
    const hi = Math.max(this._dragStartFrac, this._dragCurrentFrac);
    this._dragDay = null;
    this._dragStartFrac = null;
    this._dragCurrentFrac = null;
    const minWidth = (SNAP_MINUTES / 60 / TOTAL_HOURS) * 100 * 0.9;
    if (hi - lo < minWidth) return;
    this.newWindow = {
      Day_Of_Week__c: day,
      startTime: this._fracToTime(lo),
      endTime: this._fracToTime(hi),
      isRecurring: true
    };
    this.showModal = true;
  }

  // ── Dots menu ───────────────────────────────────────────────────────────

  handleMenuToggle(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    if (this.openMenuId === id) {
      this.openMenuId = null;
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    this.menuPos = {
      top: rect.bottom + 4,
      left: rect.left
    };
    this.openMenuId = id;
  }

  handleMenuClose() {
    this.openMenuId = null;
  }

  // ── Toggle block ────────────────────────────────────────────────────────

  async handleToggleBlock(event) {
    event.stopPropagation();
    this.openMenuId = null;
    const slotId = event.currentTarget.dataset.id;
    const win = this.windows.find((w) => w.Id === slotId);
    if (win && this._isDayPast(win.Day_Of_Week__c)) return;
    try {
      await toggleWindowBlock({ slotId });
      await this._loadWindows();
    } catch (e) {
      this._toast(
        "Error",
        e.body?.message || "Could not update window.",
        "error"
      );
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  async handleDelete(event) {
    event.stopPropagation();
    this.openMenuId = null;
    const slotId = event.currentTarget.dataset.id;
    const win = this.windows.find((w) => w.Id === slotId);
    if (win && this._isDayPast(win.Day_Of_Week__c)) return;
    // eslint-disable-next-line no-alert
    if (!confirm("Delete this window permanently?")) return;
    try {
      await deleteWindow({ slotId });
      await this._loadWindows();
      this._toast("Deleted", "Availability window removed.", "success");
    } catch (e) {
      this._toast(
        "Error",
        e.body?.message || "Could not delete window.",
        "error"
      );
    }
  }

  // ── Modal ───────────────────────────────────────────────────────────────

  handleAddWindow() {
    this.newWindow = {
      Day_Of_Week__c: "Monday",
      startTime: "08:00",
      endTime: "12:00",
      isRecurring: true
    };
    this.showModal = true;
  }

  handleCloseModal() {
    this.showModal = false;
  }

  handleDayChange(event) {
    this.newWindow = { ...this.newWindow, Day_Of_Week__c: event.detail.value };
  }

  handleTimeChange(event) {
    const field = event.currentTarget.dataset.field;
    this.newWindow = { ...this.newWindow, [field]: event.detail.value };
  }

  handleRecurringChange(event) {
    this.newWindow = { ...this.newWindow, isRecurring: event.target.checked };
  }

  async handleSave() {
    if (!this.newWindow.startTime || !this.newWindow.endTime) {
      this._toast("Validation", "Start and end time are required.", "warning");
      return;
    }
    if (this.newWindow.startTime >= this.newWindow.endTime) {
      this._toast(
        "Validation",
        "End time must be after start time.",
        "warning"
      );
      return;
    }
    this.isSaving = true;
    try {
      await saveWindow({
        dayOfWeek: this.newWindow.Day_Of_Week__c,
        startTime: this.newWindow.startTime,
        endTime: this.newWindow.endTime,
        weekStart: this._weekStart,
        isRecurring: this.newWindow.isRecurring
      });
      await this._loadWindows();
      this.showModal = false;
      this._toast(
        "Window saved",
        `${this.newWindow.Day_Of_Week__c} ${this.newWindow.startTime} – ${this.newWindow.endTime} added.`,
        "success"
      );
    } catch (e) {
      this._toast(
        "Error",
        e.body?.message || "Could not save window.",
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  _eventFrac(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    return Math.max(
      0,
      Math.min(100, ((event.clientX - rect.left) / rect.width) * 100)
    );
  }

  _snapFrac(pct) {
    const totalMinutes = TOTAL_HOURS * 60;
    const minutes = (pct / 100) * totalMinutes;
    const snapped = Math.round(minutes / SNAP_MINUTES) * SNAP_MINUTES;
    return Math.max(0, Math.min(100, (snapped / totalMinutes) * 100));
  }

  _fracToTime(pct) {
    const totalMinutes = Math.round((pct / 100) * TOTAL_HOURS * 60);
    const h = Math.floor(totalMinutes / 60) + START_HOUR;
    const m = totalMinutes % 60;
    return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
  }

  _fracToLabel(pct) {
    return this._fracToTime(pct);
  }

  _enrichWindow(w) {
    const startH = new Date(w.Start_DateTime__c).getUTCHours();
    const startM = new Date(w.Start_DateTime__c).getUTCMinutes();
    const endH = new Date(w.End_DateTime__c).getUTCHours();
    const endM = new Date(w.End_DateTime__c).getUTCMinutes();

    const startFrac = ((startH + startM / 60 - START_HOUR) / TOTAL_HOURS) * 100;
    const endFrac = ((endH + endM / 60 - START_HOUR) / TOTAL_HOURS) * 100;
    const width = endFrac - startFrac;

    const startLabel = `${String(startH).padStart(2, "0")}:${String(startM).padStart(2, "0")}`;
    const endLabel = `${String(endH).padStart(2, "0")}:${String(endM).padStart(2, "0")}`;

    const blocked = w.Is_Blocked__c;
    const recurring = w.Is_Recurring__c;
    let blockClass = "time-block";
    if (blocked) {
      blockClass += " time-block--blocked";
    } else if (!recurring) {
      blockClass += " time-block--onetime";
    } else {
      blockClass += " time-block--active";
    }
    return {
      ...w,
      startLabel,
      endLabel,
      blockStyle: `left:${startFrac}%;width:${width}%`,
      blockClass,
      toggleIcon: blocked ? "utility:check" : "utility:ban",
      toggleTitle: blocked ? "Activate window" : "Block window",
      tooltip: `${startLabel} – ${endLabel}${blocked ? " · Blocked" : ""}${!recurring ? " · One-time" : ""}`
    };
  }

  _enrichInterview(iv) {
    // Salesforce DateTime serializes as epoch ms — use local time for display
    const start = new Date(iv.startDt);
    const end   = new Date(iv.endDt);
    const startH = start.getHours();
    const startM = start.getMinutes();
    const endH   = end.getHours();
    const endM   = end.getMinutes();

    const startFrac = ((startH + startM / 60 - START_HOUR) / TOTAL_HOURS) * 100;
    const endFrac   = ((endH   + endM   / 60 - START_HOUR) / TOTAL_HOURS) * 100;
    const width = Math.max(endFrac - startFrac, 2); // min 2% so short interviews are visible

    const startLabel = `${String(startH).padStart(2, "0")}:${String(startM).padStart(2, "0")}`;
    const endLabel   = `${String(endH).padStart(2, "0")}:${String(endM).padStart(2, "0")}`;

    // < 45 min (~4.7% of 16h track) → compact: rotate text vertically
    const isCompact = width < 4.8;
    const blockClass = isCompact ? 'iv-block iv-block--compact' : 'iv-block';

    return {
      ...iv,
      startLabel,
      endLabel,
      isCompact,
      blockClass,
      blockStyle: `left:${startFrac}%;width:${width}%`,
      tooltip: `${iv.candidateName} · ${iv.stageName} · ${startLabel} – ${endLabel}`
    };
  }

  // ── Floating menu getters ───────────────────────────────────────────────

  get showMenu() { return !!this.openMenuId; }

  get menuStyle() {
    return `top:${this.menuPos.top}px;left:${this.menuPos.left}px`;
  }

  get menuWindow() {
    return this.windows.find(w => w.Id === this.openMenuId) || null;
  }

  // ── Interview side panel ────────────────────────────────────────────────

  @track selectedInterview = null;

  get showPanel() { return !!this.selectedInterview; }

  get panelStatusBadgeClass() {
    const s = this.selectedInterview?.status;
    if (s === 'Completed')         return 'iv-badge iv-badge--green';
    if (s === 'Scheduled')         return 'iv-badge iv-badge--blue';
    if (s === 'Pending_Scheduling') return 'iv-badge iv-badge--orange';
    return 'iv-badge iv-badge--gray';
  }

  get panelStatusLabel() {
    const s = this.selectedInterview?.status;
    if (s === 'Pending_Scheduling') return 'Pending Scheduling';
    return s || '—';
  }

  get panelScoreLabel() {
    const sc = this.selectedInterview?.score;
    return sc != null ? `${sc}` : '—';
  }

  get panelHasMeetingLink() {
    return !!this.selectedInterview?.meetingLink;
  }

  get panelExperienceLabel() {
    const yoe = this.selectedInterview?.candidateExperience;
    return yoe != null ? `${yoe} yr${yoe !== 1 ? 's' : ''} experience` : null;
  }

  handleInterviewClick(event) {
    event.stopPropagation();
    const interviewId = event.currentTarget.dataset.id;
    this.selectedInterview = this.interviews.find(iv => iv.interviewId === interviewId) || null;
  }

  handleClosePanel() {
    this.selectedInterview = null;
  }

  handleOpenInterviewRecord() {
    window.open(`/${this.selectedInterview.interviewId}`, "_blank");
  }

  handleOpenMeetingLink() {
    window.open(this.selectedInterview.meetingLink, "_blank");
  }

  // ── Date helpers ────────────────────────────────────────────────────────

  _currentMonday() {
    const today = new Date();
    const dow = today.getDay(); // 0=Sun, 1=Mon ... 6=Sat
    const diff = dow === 0 ? -6 : 1 - dow;
    const mon = new Date(today);
    mon.setDate(mon.getDate() + diff);
    return this._formatDate(mon);
  }

  _formatDate(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  _parseDate(str) {
    const [y, m, d] = str.split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  _toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
