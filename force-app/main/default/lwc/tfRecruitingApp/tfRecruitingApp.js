import { LightningElement, track } from 'lwc';

export default class TfRecruitingApp extends LightningElement {
  @track activeTab = 'home'; // home | jobs | track

  get isHome() { return this.activeTab === 'home'; }
  get isJobs() { return this.activeTab === 'jobs'; }
  get isTrack() { return this.activeTab === 'track'; }

  get homeTabClass() { return this.activeTab === 'home' ? 'tab active' : 'tab'; }
  get jobsTabClass() { return this.activeTab === 'jobs' ? 'tab active' : 'tab'; }
  get trackTabClass() { return this.activeTab === 'track' ? 'tab active' : 'tab'; }

  goHome = () => { this.activeTab = 'home'; };
  goJobs = () => { this.activeTab = 'jobs'; };
  goTrack = () => { this.activeTab = 'track'; };
}