import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getJobPositions from '@salesforce/apex/JobPositionController.getJobPositions';

export default class TfJobPositions extends NavigationMixin(LightningElement) {
  @track searchTerm = "";
  @track activeFilter = "All";
  @track positions = [];
  @track isLoading = true;
  @track hasError = false;

  @wire(getJobPositions)
  wiredPositions({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.positions = data.map((pos) => this._enrichPosition(pos));
      this.hasError = false;
    } else if (error) {
      this.hasError = true;
      console.error("Error loading positions:", error);
    }
  }

  _enrichPosition(pos) {
    const statusClassMap = {
      Open: "tf-badge tf-badge--open",
      Draft: "tf-badge tf-badge--draft",
      Closed: "tf-badge tf-badge--closed",
      Cancelled: "tf-badge tf-badge--cancelled"
    };

    let deadlineLabel = "";
    let isOverdue = false;
    if (pos.Application_Deadline__c) {
      const deadline = new Date(pos.Application_Deadline__c);
      const today = new Date();
      const diffDays = Math.ceil((deadline - today) / (1000 * 60 * 60 * 24));
      if (diffDays < 0) {
        deadlineLabel = "Overdue";
        isOverdue = true;
      } else if (diffDays === 0) {
        deadlineLabel = "Due today";
      } else if (diffDays <= 7) {
        deadlineLabel = `${diffDays}d left`;
      } else {
        deadlineLabel = deadline.toLocaleDateString("en-US", {
          month: "short",
          day: "numeric"
        });
      }
    }

    return {
      ...pos,
      statusClass: statusClassMap[pos.Status__c] || "tf-badge tf-badge--draft",
      deadlineLabel,
      isOverdue,
      deadlineClass: isOverdue
        ? "tf-card__deadline tf-card__deadline--overdue"
        : "tf-card__deadline",
      Open_Positions__c: pos.Open_Positions__c ?? 0,
      Filled_Positions__c: pos.Filled_Positions__c ?? 0,
      Desired_Hires__c: pos.Desired_Hires__c ?? 0
    };
  }

  get filteredPositions() {
    return this.positions.filter((pos) => {
      const matchesFilter =
        this.activeFilter === "All" || pos.Status__c === this.activeFilter;
      const term = this.searchTerm.toLowerCase();
      const matchesSearch =
        !term ||
        (pos.Title__c && pos.Title__c.toLowerCase().includes(term)) ||
        (pos.Department__c && pos.Department__c.toLowerCase().includes(term)) ||
        (pos.Required_Location__c &&
          pos.Required_Location__c.toLowerCase().includes(term));
      return matchesFilter && matchesSearch;
    });
  }

  get totalCount() {
    return this.filteredPositions.length;
  }

  get hasPositions() {
    return this.filteredPositions.length > 0;
  }

  getFilterClass(filter) {
    return `tf-filter-btn${this.activeFilter === filter ? " tf-filter-btn--active" : ""}`;
  }

  get getFilterClassAll() {
    return this.getFilterClass("All");
  }
  get getFilterClassOpen() {
    return this.getFilterClass("Open");
  }
  get getFilterClassDraft() {
    return this.getFilterClass("Draft");
  }
  get getFilterClassClosed() {
    return this.getFilterClass("Closed");
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  handleFilter(event) {
    this.activeFilter = event.currentTarget.dataset.filter;
  }

  handleCardClick(event) {
    const recordId = event.currentTarget.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "Job_Position__c",
        actionName: "view"
      }
    });
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Job_Position__c",
        actionName: "new"
      }
    });
  }
}
