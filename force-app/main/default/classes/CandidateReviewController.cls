public with sharing class CandidateReviewController {
  // v4: force-bump for sync diagnosis
  private static final List<String> APP_FIELDS = new List<String>{
    'Id',
    'Name',
    'AI_Score__c',
    'Skills_Match_Score__c',
    'Experience_Score__c',
    'Education_Score__c',
    'Selection_Status__c',
    'Application_Date__c',
    'Extracted_Skills__c',
    'Filter_Review_Status__c',
    'Passed_Hard_Filter__c',
    'AI_Filter_Decision__c',
    'Current_Interview_Stage__c',
    'Candidate__r.FirstName__c',
    'Candidate__r.LastName__c',
    'Candidate__r.Name',
    'Candidate__r.Email__c',
    'Candidate__r.Years_of_Experience__c',
    'Candidate__r.Education_Level__c',
    'Extracted_Experience__c',
    'Extracted_Education__c'
  };

  public class CandidateCard implements Comparable {
    @AuraEnabled
    public Id applicationId;
    @AuraEnabled
    public String applicationName;
    @AuraEnabled
    public String candidateName;
    @AuraEnabled
    public String candidateInitials;
    @AuraEnabled
    public Decimal aiScore;
    @AuraEnabled
    public Decimal skillsScore;
    @AuraEnabled
    public Decimal experienceScore;
    @AuraEnabled
    public Decimal educationScore;
    @AuraEnabled
    public String selectionStatus;
    @AuraEnabled
    public String applicationDate;
    @AuraEnabled
    public String extractedSkills;
    @AuraEnabled
    public Id currentStageId;
    @AuraEnabled
    public String candidateEmail;
    @AuraEnabled
    public Decimal yearsOfExperience;
    @AuraEnabled
    public String educationLevel;
    @AuraEnabled
    public Decimal extractedExperience;
    @AuraEnabled
    public String extractedEducation;
    @AuraEnabled
    public Decimal interviewScore;
    @AuraEnabled
    public String interviewStatus; // e.g. "Completed", "Scheduled", "No Interview"
    @AuraEnabled
    public String applicationStage; // e.g. "Offer", "Hired" (used for the synthetic Hired column)
    @AuraEnabled
    public Integer interviewsCompleted;
    @AuraEnabled
    public Integer interviewsTotal;
    @AuraEnabled
    public Boolean invitationSent;
    @AuraEnabled
    public Datetime scheduledDateTime;
    @AuraEnabled
    public List<InterviewerReview> interviewerReviews;
    @AuraEnabled
    public String rejectionReason;

    public Integer compareTo(Object other) {
      CandidateCard o = (CandidateCard) other;
      Decimal thisVal = this.interviewScore != null ? this.interviewScore : -1;
      Decimal otherVal = o.interviewScore != null ? o.interviewScore : -1;
      if (otherVal > thisVal)
        return 1;
      if (otherVal < thisVal)
        return -1;
      return 0;
    }
  }

  public class InterviewerReview {
    @AuraEnabled
    public String interviewerName;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String recommendation;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public String stageName;
  }

  public class StageProgress {
    @AuraEnabled
    public Id stageId;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public Decimal stageNumber;
  }

  public class StageReviewData {
    @AuraEnabled
    public Id stageId;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public Decimal stageNumber;
    @AuraEnabled
    public Boolean isFirstStage;
    @AuraEnabled
    public Decimal passingThreshold;
    @AuraEnabled
    public List<StageProgress> allStages;
    @AuraEnabled
    public List<CandidateCard> activeCandidates;
    @AuraEnabled
    public List<CandidateCard> waitingCandidates;
    @AuraEnabled
    public Integer waitingTotal;
    @AuraEnabled
    public List<CandidateCard> rejectedCandidates;
  }

  public class PipelineStageOverview {
    @AuraEnabled
    public Id stageId;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public Decimal stageNumber;
    @AuraEnabled
    public Integer activeCount;
    @AuraEnabled
    public List<CandidateCard> topCandidates;
    @AuraEnabled
    public Boolean isHired;
  }

  public class UndoImpact {
    @AuraEnabled
    public Boolean requiresConfirmation;
    @AuraEnabled
    public Boolean invitationSent;
    @AuraEnabled
    public Boolean hasScheduledInterview;
    @AuraEnabled
    public Boolean hasCompletedInterview;
    @AuraEnabled
    public Datetime scheduledDateTime;
    @AuraEnabled
    public Integer affectedInterviewCount;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public String candidateName;
  }

  public class OfferCapacityWarning {
    @AuraEnabled
    public Boolean hasWarning;
    @AuraEnabled
    public Decimal desiredHires;
    @AuraEnabled
    public Decimal filledPositions;
    @AuraEnabled
    public Decimal openPositions;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Boolean requiresFinalizationDecision;
    @AuraEnabled
    public String postFillStrategy;
  }

  @AuraEnabled(cacheable=false)
  public static List<PipelineStageOverview> getPipelineOverview(
    Id jobPositionId
  ) {
    List<Interview_Stage__c> stages = [
      SELECT Id, Name, Stage_Number__c
      FROM Interview_Stage__c
      WHERE Job_Position__c = :jobPositionId
      ORDER BY Stage_Number__c ASC
    ];

    Set<Id> stageIds = new Set<Id>();
    for (Interview_Stage__c s : stages) {
      stageIds.add(s.Id);
    }

    // Count active candidates per stage (exclude those already moved to Offer/Hired/Withdrawn/Rejected)
    Map<Id, Integer> countByStage = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Current_Interview_Stage__c stageId, COUNT(Id) cnt
      FROM Job_Application__c
      WHERE
        Job_Position__c = :jobPositionId
        AND Current_Interview_Stage__c IN :stageIds
        AND Selection_Status__c = 'Selected'
        AND (Stage__c = NULL
        OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
      GROUP BY Current_Interview_Stage__c
    ]) {
      countByStage.put((Id) ar.get('stageId'), (Integer) ar.get('cnt'));
    }

    // Top 3 candidates per stage (same exclusion)
    List<Job_Application__c> allActive = [
      SELECT
        Id,
        Current_Interview_Stage__c,
        Application_Date__c,
        Candidate__r.FirstName__c,
        Candidate__r.LastName__c
      FROM Job_Application__c
      WHERE
        Job_Position__c = :jobPositionId
        AND Current_Interview_Stage__c IN :stageIds
        AND Selection_Status__c = 'Selected'
        AND (Stage__c = NULL
        OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
      ORDER BY AI_Score__c DESC NULLS LAST
    ];

    Map<Id, List<CandidateCard>> topByStage = new Map<Id, List<CandidateCard>>();
    for (Job_Application__c app : allActive) {
      Id sid = app.Current_Interview_Stage__c;
      if (!topByStage.containsKey(sid)) {
        topByStage.put(sid, new List<CandidateCard>());
      }
      if (topByStage.get(sid).size() < 3) {
        CandidateCard card = new CandidateCard();
        card.applicationId = app.Id;
        String fn = app.Candidate__r?.FirstName__c;
        String ln = app.Candidate__r?.LastName__c;
        card.candidateName = (fn != null ||
          ln != null)
          ? ((fn != null ? fn : '') + ' ' + (ln != null ? ln : '')).trim()
          : 'Unknown';
        card.candidateInitials = buildInitials(fn, ln);
        card.applicationDate = app.Application_Date__c != null
          ? String.valueOf(app.Application_Date__c)
          : null;
        topByStage.get(sid).add(card);
      }
    }

    List<PipelineStageOverview> result = new List<PipelineStageOverview>();
    for (Interview_Stage__c s : stages) {
      PipelineStageOverview ov = new PipelineStageOverview();
      ov.stageId = s.Id;
      ov.stageName = s.Name;
      ov.stageNumber = s.Stage_Number__c;
      ov.activeCount = countByStage.containsKey(s.Id)
        ? countByStage.get(s.Id)
        : 0;
      ov.topCandidates = topByStage.containsKey(s.Id)
        ? topByStage.get(s.Id)
        : new List<CandidateCard>();
      ov.isHired = false;
      result.add(ov);
    }

    // Synthetic "Hired" column is meaningless when no interview stages are configured.
    if (stages.isEmpty()) {
      return result;
    }

    // Synthetic "Hired" column: Stage__c in (Offer, Hired). Hired listed first.
    PipelineStageOverview hiredOv = new PipelineStageOverview();
    hiredOv.stageId = null;
    hiredOv.stageName = 'Hired';
    hiredOv.stageNumber = null;
    hiredOv.isHired = true;
    hiredOv.topCandidates = new List<CandidateCard>();

    List<Job_Application__c> hiredApps = [
      SELECT
        Id,
        Stage__c,
        Application_Date__c,
        Candidate__r.FirstName__c,
        Candidate__r.LastName__c
      FROM Job_Application__c
      WHERE Job_Position__c = :jobPositionId AND Stage__c IN ('Offer', 'Hired')
      ORDER BY Stage__c ASC, Application_Date__c DESC NULLS LAST
    ];
    hiredOv.activeCount = hiredApps.size();
    for (Job_Application__c app : hiredApps) {
      if (hiredOv.topCandidates.size() >= 3)
        break;
      CandidateCard card = new CandidateCard();
      card.applicationId = app.Id;
      String fn = app.Candidate__r?.FirstName__c;
      String ln = app.Candidate__r?.LastName__c;
      card.candidateName = (fn != null ||
        ln != null)
        ? ((fn != null ? fn : '') + ' ' + (ln != null ? ln : '')).trim()
        : 'Unknown';
      card.candidateInitials = buildInitials(fn, ln);
      card.applicationDate = app.Application_Date__c != null
        ? String.valueOf(app.Application_Date__c)
        : null;
      card.applicationStage = app.Stage__c;
      hiredOv.topCandidates.add(card);
    }
    result.add(hiredOv);

    return result;
  }

  /**
   * Returns two lists for a given stage:
   * - activeCandidates: promoted to this stage (Current_Interview_Stage__c = stageId, Selected)
   * - waitingCandidates: eligible pool for promotion into this stage
   *
   * For stage 1: waiting = all new (null) or Pending applications not yet in any stage
   * For stage N: waiting = all Selected applications in stage N-1
   */
  private static final Integer WAITING_PAGE_SIZE = 20;

  @AuraEnabled
  public static StageReviewData getCandidatesForStage(
    Id jobPositionId,
    Id stageId,
    Integer waitingOffset
  ) {
    Integer offset = waitingOffset != null ? waitingOffset : 0;

    Interview_Stage__c stage = [
      SELECT Id, Name, Stage_Number__c, Passing_Threshold__c
      FROM Interview_Stage__c
      WHERE Id = :stageId AND Job_Position__c = :jobPositionId
      LIMIT 1
    ];

    StageReviewData result = new StageReviewData();
    result.stageId = stage.Id;
    result.stageName = stage.Name;
    result.stageNumber = stage.Stage_Number__c;
    result.passingThreshold = stage.Passing_Threshold__c;

    // Build stage progress list for the timeline
    List<Interview_Stage__c> allStageDefs = [
      SELECT Id, Name, Stage_Number__c
      FROM Interview_Stage__c
      WHERE Job_Position__c = :jobPositionId
      ORDER BY Stage_Number__c ASC
    ];
    List<StageProgress> stageList = new List<StageProgress>();
    Map<Id, String> stageNameById = new Map<Id, String>();
    for (Interview_Stage__c s : allStageDefs) {
      StageProgress sp = new StageProgress();
      sp.stageId = s.Id;
      sp.stageName = s.Name;
      sp.stageNumber = s.Stage_Number__c;
      stageList.add(sp);
      stageNameById.put(s.Id, s.Name);
    }
    result.allStages = stageList;

    // Active: candidates promoted to THIS stage (excluding those already offered/hired/withdrawn)
    List<Job_Application__c> activeApps = [
      SELECT
        Id,
        Name,
        AI_Score__c,
        Skills_Match_Score__c,
        Experience_Score__c,
        Education_Score__c,
        Selection_Status__c,
        Stage__c,
        Application_Date__c,
        Extracted_Skills__c,
        Filter_Review_Status__c,
        Passed_Hard_Filter__c,
        AI_Filter_Decision__c,
        Current_Interview_Stage__c,
        Candidate__r.FirstName__c,
        Candidate__r.LastName__c,
        Candidate__r.Name,
        Candidate__r.Email__c,
        Candidate__r.Years_of_Experience__c,
        Candidate__r.Education_Level__c,
        Extracted_Experience__c,
        Extracted_Education__c
      FROM Job_Application__c
      WHERE
        Job_Position__c = :jobPositionId
        AND Current_Interview_Stage__c = :stageId
        AND Selection_Status__c = 'Selected'
        AND (Stage__c = NULL
        OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
      ORDER BY AI_Score__c DESC NULLS LAST
    ];

    Boolean firstStage = isFirstStage(jobPositionId, stage.Stage_Number__c);
    result.isFirstStage = firstStage;

    result.activeCandidates = buildCards(activeApps);
    enrichWithInterviewStatus(result.activeCandidates, stageId, stageNameById);

    // Rejected at THIS stage, plus waiting-list rejections (null stage) on the first stage view
    List<Job_Application__c> rejectedApps = [
      SELECT
        Id, Name, AI_Score__c, Skills_Match_Score__c, Experience_Score__c,
        Education_Score__c, Selection_Status__c, Stage__c, Application_Date__c,
        Extracted_Skills__c, Filter_Review_Status__c, Passed_Hard_Filter__c,
        AI_Filter_Decision__c, Current_Interview_Stage__c, Filter_Rejection_Reason__c,
        Candidate__r.FirstName__c, Candidate__r.LastName__c, Candidate__r.Name,
        Candidate__r.Email__c, Candidate__r.Years_of_Experience__c,
        Candidate__r.Education_Level__c, Extracted_Experience__c, Extracted_Education__c
      FROM Job_Application__c
      WHERE Job_Position__c = :jobPositionId
        AND Stage__c = 'Rejected'
        AND Current_Interview_Stage__c = :stageId
      ORDER BY AI_Score__c DESC NULLS LAST
    ];
    if (firstStage) {
      rejectedApps.addAll([
        SELECT
          Id, Name, AI_Score__c, Skills_Match_Score__c, Experience_Score__c,
          Education_Score__c, Selection_Status__c, Stage__c, Application_Date__c,
          Extracted_Skills__c, Filter_Review_Status__c, Passed_Hard_Filter__c,
          AI_Filter_Decision__c, Current_Interview_Stage__c, Filter_Rejection_Reason__c,
          Candidate__r.FirstName__c, Candidate__r.LastName__c, Candidate__r.Name,
          Candidate__r.Email__c, Candidate__r.Years_of_Experience__c,
          Candidate__r.Education_Level__c, Extracted_Experience__c, Extracted_Education__c
        FROM Job_Application__c
        WHERE Job_Position__c = :jobPositionId
          AND Stage__c = 'Rejected'
          AND Current_Interview_Stage__c = NULL
        ORDER BY AI_Score__c DESC NULLS LAST
      ]);
    }
    result.rejectedCandidates = buildCards(rejectedApps);

    if (firstStage) {
      result.waitingTotal = [
        SELECT COUNT()
        FROM Job_Application__c
        WHERE
          Job_Position__c = :jobPositionId
          AND (Selection_Status__c = 'Pending'
          OR Selection_Status__c = NULL)
          AND Current_Interview_Stage__c = NULL
      ];
      List<Job_Application__c> waitingApps = [
        SELECT
          Id,
          Name,
          AI_Score__c,
          Skills_Match_Score__c,
          Experience_Score__c,
          Education_Score__c,
          Selection_Status__c,
          Stage__c,
          Application_Date__c,
          Extracted_Skills__c,
          Filter_Review_Status__c,
          Passed_Hard_Filter__c,
          AI_Filter_Decision__c,
          Current_Interview_Stage__c,
          Candidate__r.FirstName__c,
          Candidate__r.LastName__c,
          Candidate__r.Name,
          Candidate__r.Email__c,
          Candidate__r.Years_of_Experience__c,
          Candidate__r.Education_Level__c,
          Extracted_Experience__c,
          Extracted_Education__c
        FROM Job_Application__c
        WHERE
          Job_Position__c = :jobPositionId
          AND (Selection_Status__c = 'Pending'
          OR Selection_Status__c = NULL)
          AND Current_Interview_Stage__c = NULL
        ORDER BY AI_Score__c DESC NULLS LAST
        LIMIT :WAITING_PAGE_SIZE
        OFFSET :offset
      ];
      result.waitingCandidates = buildCards(waitingApps);
    } else {
      Id previousStageId = getPreviousStageId(
        jobPositionId,
        stage.Stage_Number__c
      );
      if (previousStageId != null) {
        result.waitingTotal = [
          SELECT COUNT()
          FROM Job_Application__c
          WHERE
            Job_Position__c = :jobPositionId
            AND Current_Interview_Stage__c = :previousStageId
            AND Selection_Status__c = 'Selected'
            AND (Stage__c = NULL
            OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
        ];
        List<Job_Application__c> waitingApps = [
          SELECT
            Id,
            Name,
            AI_Score__c,
            Skills_Match_Score__c,
            Experience_Score__c,
            Education_Score__c,
            Selection_Status__c,
            Stage__c,
            Application_Date__c,
            Extracted_Skills__c,
            Filter_Review_Status__c,
            Passed_Hard_Filter__c,
            AI_Filter_Decision__c,
            Current_Interview_Stage__c,
            Candidate__r.FirstName__c,
            Candidate__r.LastName__c,
            Candidate__r.Name,
            Candidate__r.Email__c,
            Candidate__r.Years_of_Experience__c,
            Candidate__r.Education_Level__c,
            Extracted_Experience__c,
            Extracted_Education__c
          FROM Job_Application__c
          WHERE
            Job_Position__c = :jobPositionId
            AND Current_Interview_Stage__c = :previousStageId
            AND Selection_Status__c = 'Selected'
            AND (Stage__c = NULL
            OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
          ORDER BY AI_Score__c DESC NULLS LAST
          LIMIT :WAITING_PAGE_SIZE
          OFFSET :offset
        ];
        List<CandidateCard> waitCards = buildCards(waitingApps);
        enrichWithInterviewStatus(waitCards, previousStageId, stageNameById);
        waitCards.sort();
        result.waitingCandidates = waitCards;
      } else {
        result.waitingTotal = 0;
        result.waitingCandidates = new List<CandidateCard>();
      }
    }

    return result;
  }

  /**
   * Hired view: active = Offer/Hired candidates; waiting = last-stage selected candidates eligible for an offer.
   */
  @AuraEnabled
  public static StageReviewData getHiredReviewData(Id jobPositionId) {
    StageReviewData result = new StageReviewData();
    result.stageId = null;
    result.stageName = 'Hired';
    result.isFirstStage = false;

    // Find the last stage for the position (waiting list = its selected candidates)
    List<Interview_Stage__c> allStageDefs = [
      SELECT Id, Name, Stage_Number__c
      FROM Interview_Stage__c
      WHERE Job_Position__c = :jobPositionId
      ORDER BY Stage_Number__c ASC
    ];
    List<StageProgress> stageList = new List<StageProgress>();
    Map<Id, String> stageNameById = new Map<Id, String>();
    Id lastStageId = null;
    for (Interview_Stage__c s : allStageDefs) {
      StageProgress sp = new StageProgress();
      sp.stageId = s.Id;
      sp.stageName = s.Name;
      sp.stageNumber = s.Stage_Number__c;
      stageList.add(sp);
      stageNameById.put(s.Id, s.Name);
      lastStageId = s.Id; // overwrite — last iteration wins
    }
    result.allStages = stageList;

    // Active: Offer/Hired candidates (Hired first, then Offer)
    List<Job_Application__c> activeApps = [
      SELECT
        Id,
        Name,
        AI_Score__c,
        Skills_Match_Score__c,
        Experience_Score__c,
        Education_Score__c,
        Selection_Status__c,
        Stage__c,
        Application_Date__c,
        Extracted_Skills__c,
        Filter_Review_Status__c,
        Passed_Hard_Filter__c,
        AI_Filter_Decision__c,
        Current_Interview_Stage__c,
        Candidate__r.FirstName__c,
        Candidate__r.LastName__c,
        Candidate__r.Name,
        Candidate__r.Email__c,
        Candidate__r.Years_of_Experience__c,
        Candidate__r.Education_Level__c,
        Extracted_Experience__c,
        Extracted_Education__c
      FROM Job_Application__c
      WHERE Job_Position__c = :jobPositionId AND Stage__c IN ('Offer', 'Hired')
      ORDER BY Stage__c ASC, Application_Date__c DESC NULLS LAST
    ];
    result.activeCandidates = buildCards(activeApps);

    // Waiting: candidates in the LAST stage, Selected, not already offered/withdrawn
    List<Job_Application__c> waitingApps = new List<Job_Application__c>();
    if (lastStageId != null) {
      waitingApps = [
        SELECT
          Id,
          Name,
          AI_Score__c,
          Skills_Match_Score__c,
          Experience_Score__c,
          Education_Score__c,
          Selection_Status__c,
          Stage__c,
          Application_Date__c,
          Extracted_Skills__c,
          Filter_Review_Status__c,
          Passed_Hard_Filter__c,
          AI_Filter_Decision__c,
          Current_Interview_Stage__c,
          Candidate__r.FirstName__c,
          Candidate__r.LastName__c,
          Candidate__r.Name,
          Candidate__r.Email__c,
          Candidate__r.Years_of_Experience__c,
          Candidate__r.Education_Level__c,
          Extracted_Experience__c,
          Extracted_Education__c
        FROM Job_Application__c
        WHERE
          Job_Position__c = :jobPositionId
          AND Current_Interview_Stage__c = :lastStageId
          AND Selection_Status__c = 'Selected'
          AND (Stage__c = NULL
          OR Stage__c NOT IN ('Offer', 'Hired', 'Withdrawn', 'Rejected'))
      ];
      List<CandidateCard> waitCards = buildCards(waitingApps);
      enrichWithInterviewStatus(waitCards, lastStageId, stageNameById);
      waitCards.sort();
      result.waitingCandidates = waitCards;
    } else {
      result.waitingCandidates = new List<CandidateCard>();
    }

    return result;
  }

  @AuraEnabled(cacheable=false)
  public static OfferCapacityWarning getOfferCapacityWarning(Id applicationId) {
    Job_Application__c app = [
      SELECT Id, Job_Position__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    // Keep the capacity counters fresh even if the job page has stale values.
    if (app.Job_Position__c != null) {
      JobPositionCapacityService.syncCapacityForJobPositions(
        new Set<Id>{ app.Job_Position__c }
      );
    }

    JobPositionCapacityService.CapacitySnapshot snapshot = JobPositionCapacityService.getCapacitySnapshot(
      app.Job_Position__c
    );

    OfferCapacityWarning warning = new OfferCapacityWarning();
    warning.hasWarning =
      snapshot != null &&
      snapshot.desiredHires > 0 &&
      snapshot.openPositions <= 0;
    warning.desiredHires = snapshot != null ? snapshot.desiredHires : 0;
    warning.filledPositions = snapshot != null ? snapshot.filledPositions : 0;
    warning.openPositions = snapshot != null ? snapshot.openPositions : 0;
    warning.requiresFinalizationDecision =
      snapshot != null &&
      snapshot.requiresFinalizationDecision == true;
    warning.postFillStrategy = snapshot != null
      ? snapshot.postFillStrategy
      : null;
    warning.message = warning.hasWarning
      ? 'This job has no open positions left. Review the target before continuing.'
      : null;
    return warning;
  }

  @AuraEnabled(cacheable=false)
  public static OfferCapacityWarning getAcceptCapacityWarning(
    Id applicationId
  ) {
    OfferCapacityWarning warning = getOfferCapacityWarning(applicationId);
    if (warning != null && warning.hasWarning == true) {
      warning.message = 'This hire will exceed the desired number of hires. Review the target before continuing.';
    }
    return warning;
  }

  @AuraEnabled
  public static void extendOffer(Id applicationId, Boolean offerAnyway) {
    Job_Application__c existingApp = [
      SELECT Id, Job_Position__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    // Recalculate first so the warning uses the real current Hired count.
    if (existingApp.Job_Position__c != null) {
      JobPositionCapacityService.syncCapacityForJobPositions(
        new Set<Id>{ existingApp.Job_Position__c }
      );
    }

    JobPositionCapacityService.CapacitySnapshot snapshot = JobPositionCapacityService.getCapacitySnapshot(
      existingApp.Job_Position__c
    );

    if (
      snapshot != null &&
      snapshot.desiredHires > 0 &&
      snapshot.openPositions <= 0 &&
      offerAnyway != true
    ) {
      throw new AuraHandledException(
        'This job has no open positions left. Confirm the offer anyway or increase desired hires before continuing.'
      );
    }

    Job_Application__c app = new Job_Application__c(Id = applicationId);
    app.Stage__c = 'Offer';

    Boolean oldBypass = JobPositionCapacityService.bypassPipelineProgressGuard;
    JobPositionCapacityService.bypassPipelineProgressGuard =
      offerAnyway == true;
    try {
      update app;
    } finally {
      JobPositionCapacityService.bypassPipelineProgressGuard = oldBypass;
    }
  }

  @AuraEnabled
  public static void markOfferAccepted(Id applicationId) {
    markOfferAcceptedWithCapacityDecision(applicationId, false);
  }

  @AuraEnabled
  public static void markOfferAcceptedWithCapacityDecision(
    Id applicationId,
    Boolean acceptAnyway
  ) {
    Job_Application__c existingApp = [
      SELECT Id, Job_Position__c, Stage__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (existingApp.Job_Position__c != null) {
      JobPositionCapacityService.syncCapacityForJobPositions(
        new Set<Id>{ existingApp.Job_Position__c }
      );
      JobPositionCapacityService.CapacitySnapshot snapshot = JobPositionCapacityService.getCapacitySnapshot(
        existingApp.Job_Position__c
      );

      if (
        snapshot != null &&
        snapshot.desiredHires > 0 &&
        snapshot.openPositions <= 0 &&
        existingApp.Stage__c != 'Hired' &&
        acceptAnyway != true
      ) {
        throw new AuraHandledException(
          'This job has already reached its hiring target. Confirm this hire anyway or increase desired hires before continuing.'
        );
      }
    }

    Job_Application__c app = new Job_Application__c(Id = applicationId);
    app.Stage__c = 'Hired';

    Boolean oldBypass = JobPositionCapacityService.bypassPipelineProgressGuard;
    JobPositionCapacityService.bypassPipelineProgressGuard =
      acceptAnyway == true;
    try {
      update app;
    } finally {
      JobPositionCapacityService.bypassPipelineProgressGuard = oldBypass;
    }

    if (existingApp.Job_Position__c != null) {
      JobPositionCapacityService.enqueueCapacitySyncForJobPositions(
        new Set<Id>{ existingApp.Job_Position__c }
      );
    }
  }

  @AuraEnabled
  public static void markOfferDeclined(Id applicationId) {
    Job_Application__c existing = [
      SELECT Id, Job_Position__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Job_Application__c app = new Job_Application__c(Id = applicationId);
    app.Stage__c = 'Withdrawn';
    update app;
    // Declined offer frees up a position — re-sync so open counter reflects reality.
    if (existing.Job_Position__c != null) {
      JobPositionCapacityService.enqueueCapacitySyncForJobPositions(
        new Set<Id>{ existing.Job_Position__c }
      );
    }
  }

  @AuraEnabled
  public static void promoteCandidate(Id applicationId, Id stageId) {
    if (applicationId == null || stageId == null) {
      throw new AuraHandledException(
        'Application and interview stage are required.'
      );
    }

    // FOR UPDATE locks the row so a second concurrent promote on the same
    // application waits until this transaction commits, preventing double-promotion.
    Job_Application__c existingApp = [
      SELECT
        Id,
        Job_Position__c,
        Current_Interview_Stage__c,
        Selection_Status__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];

    if (
      existingApp.Current_Interview_Stage__c == stageId &&
      existingApp.Selection_Status__c == 'Selected'
    ) {
      throw new AuraHandledException(
        'This candidate has already been promoted to this stage.'
      );
    }

    Interview_Stage__c selectedStage = [
      SELECT Id, Job_Position__c
      FROM Interview_Stage__c
      WHERE Id = :stageId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (existingApp.Job_Position__c != selectedStage.Job_Position__c) {
      throw new AuraHandledException(
        'The selected interview stage does not belong to this application job position.'
      );
    }

    JobPositionCapacityService.ensureJobNotFinalizedForPipeline(
      existingApp.Job_Position__c
    );

    Database.update(
      new Job_Application__c(
        Id = applicationId,
        Current_Interview_Stage__c = stageId,
        Selection_Status__c = 'Selected',
        Stage__c = 'Interview'
      ),
      AccessLevel.SYSTEM_MODE
    );

    if (!hasActiveInterview(applicationId, stageId)) {
      JobApplicationInterviewSchedulingService.createPendingSchedulingInterviews(
        new Set<Id>{ applicationId }
      );
    }

    if (!hasActiveInterview(applicationId, stageId)) {
      throw new AuraHandledException(
        'No interview was created. Check that the stage has team members and valid availability slots.'
      );
    }
  }

  @AuraEnabled
  public static UndoImpact getUndoImpact(Id applicationId) {
    Job_Application__c app = [
      SELECT
        Id,
        Current_Interview_Stage__c,
        Current_Interview_Stage__r.Name,
        Candidate__r.FirstName__c,
        Candidate__r.LastName__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      LIMIT 1
    ];

    UndoImpact impact = new UndoImpact();
    impact.invitationSent = false;
    impact.hasScheduledInterview = false;
    impact.hasCompletedInterview = false;
    impact.affectedInterviewCount = 0;
    impact.stageName = app.Current_Interview_Stage__r != null
      ? app.Current_Interview_Stage__r.Name
      : null;
    String fn = app.Candidate__r != null ? app.Candidate__r.FirstName__c : null;
    String ln = app.Candidate__r != null ? app.Candidate__r.LastName__c : null;
    impact.candidateName = ((fn != null ? fn : '') +
      ' ' +
      (ln != null ? ln : ''))
      .trim();

    if (app.Current_Interview_Stage__c == null) {
      impact.requiresConfirmation = false;
      return impact;
    }

    for (Interview__c iv : [
      SELECT Id, Status__c, Invitation_Sent__c, Scheduled_DateTime__c
      FROM Interview__c
      WHERE
        Job_Application__c = :applicationId
        AND Interview_Stage__c = :app.Current_Interview_Stage__c
    ]) {
      impact.affectedInterviewCount++;
      if (iv.Invitation_Sent__c == true) {
        impact.invitationSent = true;
      }
      if (iv.Status__c == 'Scheduled') {
        impact.hasScheduledInterview = true;
        if (
          impact.scheduledDateTime == null ||
          (iv.Scheduled_DateTime__c != null &&
          iv.Scheduled_DateTime__c < impact.scheduledDateTime)
        ) {
          impact.scheduledDateTime = iv.Scheduled_DateTime__c;
        }
      }
      if (iv.Status__c == 'Completed') {
        impact.hasCompletedInterview = true;
      }
    }

    impact.requiresConfirmation =
      impact.invitationSent ||
      impact.hasScheduledInterview ||
      impact.hasCompletedInterview;
    return impact;
  }

  @AuraEnabled
  public static void undoPromotion(Id applicationId, String reason) {
    Job_Application__c app = [
      SELECT
        Id,
        Current_Interview_Stage__c,
        Current_Interview_Stage__r.Stage_Number__c,
        Current_Interview_Stage__r.Job_Position__c
      FROM Job_Application__c
      WHERE Id = :applicationId
      LIMIT 1
    ];

    List<Interview__c> stageInterviews = new List<Interview__c>();
    if (app.Current_Interview_Stage__c != null) {
      stageInterviews = [
        SELECT Id, Status__c, Invitation_Sent__c, Cancellation_Reason__c
        FROM Interview__c
        WHERE
          Job_Application__c = :applicationId
          AND Interview_Stage__c = :app.Current_Interview_Stage__c
      ];
    }

    Boolean reasonRequired = false;
    for (Interview__c iv : stageInterviews) {
      if (
        iv.Invitation_Sent__c == true ||
        iv.Status__c == 'Scheduled' ||
        iv.Status__c == 'Completed'
      ) {
        reasonRequired = true;
        break;
      }
    }
    if (reasonRequired && String.isBlank(reason)) {
      throw new AuraHandledException(
        'A reason is required: the candidate was already notified, scheduled, or interviewed.'
      );
    }

    List<Interview__c> toUpdate = new List<Interview__c>();
    for (Interview__c iv : stageInterviews) {
      // Leave Completed interviews intact — they're a historical record.
      if (iv.Status__c == 'Completed')
        continue;
      iv.Status__c = 'Cancelled';
      iv.Invitation_Sent__c = false;
      if (String.isNotBlank(reason)) {
        iv.Cancellation_Reason__c = reason.left(255);
      }
      toUpdate.add(iv);
    }
    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }

    // Find the previous stage (Stage_Number - 1) so the candidate goes back
    // to where they came from, not all the way to the waiting list.
    Id previousStageId = null;
    if (app.Current_Interview_Stage__c != null) {
      Decimal currentNumber = app.Current_Interview_Stage__r.Stage_Number__c;
      Id jobPositionId = app.Current_Interview_Stage__r.Job_Position__c;
      if (currentNumber != null && currentNumber > 1 && jobPositionId != null) {
        List<Interview_Stage__c> prevStages = [
          SELECT Id
          FROM Interview_Stage__c
          WHERE
            Job_Position__c = :jobPositionId
            AND Stage_Number__c = :(currentNumber - 1)
          LIMIT 1
        ];
        if (!prevStages.isEmpty()) {
          previousStageId = prevStages[0].Id;
        }
      }
    }

    if (previousStageId != null) {
      app.Current_Interview_Stage__c = previousStageId;
      app.Selection_Status__c = 'Selected';
      app.Stage__c = 'Interview';
    } else {
      app.Current_Interview_Stage__c = null;
      app.Selection_Status__c = 'Pending';
      app.Stage__c = 'New';
    }
    update app;
  }

  @AuraEnabled
  public static void rejectCandidate(Id applicationId, String reason) {
    if (String.isBlank(reason)) {
      throw new AuraHandledException('A rejection reason is required.');
    }
    Job_Application__c app = new Job_Application__c(Id = applicationId);
    app.Selection_Status__c = 'Rejected';
    app.Stage__c = 'Rejected';
    app.Filter_Rejection_Reason__c = reason;
    update app;
  }

  private static Boolean hasActiveInterview(Id applicationId, Id stageId) {
    return [
        SELECT COUNT()
        FROM Interview__c
        WHERE
          Job_Application__c = :applicationId
          AND Interview_Stage__c = :stageId
          AND Status__c IN ('Pending_Scheduling', 'Scheduled')
        WITH SYSTEM_MODE
      ] > 0;
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  private static List<CandidateCard> buildCards(List<Job_Application__c> apps) {
    List<CandidateCard> cards = new List<CandidateCard>();
    for (Job_Application__c app : apps) {
      CandidateCard card = new CandidateCard();
      card.applicationId = app.Id;
      card.applicationName = app.Name;
      String fn = app.Candidate__r?.FirstName__c;
      String ln = app.Candidate__r?.LastName__c;
      card.candidateName = (fn != null ||
        ln != null)
        ? ((fn != null ? fn : '') + ' ' + (ln != null ? ln : '')).trim()
        : 'Unknown';
      card.candidateInitials = buildInitials(fn, ln);
      card.aiScore = app.AI_Score__c;
      card.skillsScore = app.Skills_Match_Score__c;
      card.experienceScore = app.Experience_Score__c;
      card.educationScore = app.Education_Score__c;
      card.selectionStatus = app.Selection_Status__c;
      card.applicationDate = app.Application_Date__c != null
        ? String.valueOf(app.Application_Date__c)
        : null;
      card.extractedSkills = app.Extracted_Skills__c;
      card.currentStageId = app.Current_Interview_Stage__c;
      card.candidateEmail = app.Candidate__r?.Email__c;
      card.yearsOfExperience = app.Candidate__r?.Years_of_Experience__c;
      card.educationLevel = app.Candidate__r?.Education_Level__c;
      card.extractedExperience = app.Extracted_Experience__c;
      card.extractedEducation = app.Extracted_Education__c;
      card.applicationStage = app.Stage__c;
      card.rejectionReason = app.Filter_Rejection_Reason__c;
      cards.add(card);
    }
    return cards;
  }

  private static void enrichWithInterviewStatus(
    List<CandidateCard> cards,
    Id currentStageId,
    Map<Id, String> stageNameById
  ) {
    Set<Id> appIds = new Set<Id>();
    for (CandidateCard c : cards) {
      appIds.add(c.applicationId);
    }
    if (appIds.isEmpty())
      return;

    // Query ALL interviews for these apps across all stages
    // currentStageId drives table-level aggregates; all stages shown in expanded detail
    List<Interview__c> interviews = [
      SELECT
        Job_Application__c,
        Interview_Stage__c,
        Status__c,
        Score__c,
        Invitation_Sent__c,
        Scheduled_DateTime__c,
        Interviewer__r.Name,
        Notes__c,
        Recommendation__c
      FROM Interview__c
      WHERE Job_Application__c IN :appIds
      ORDER BY
        Interview_Stage__r.Stage_Number__c ASC NULLS LAST,
        Score__c DESC NULLS LAST
    ];

    Map<Id, Integer> totalByApp = new Map<Id, Integer>();
    Map<Id, Integer> completedByApp = new Map<Id, Integer>();
    Map<Id, Decimal> scoreSumByApp = new Map<Id, Decimal>();
    Map<Id, Integer> scoredByApp = new Map<Id, Integer>();
    Map<Id, String> worstStatusByApp = new Map<Id, String>();
    Map<Id, Boolean> invitedByApp = new Map<Id, Boolean>();
    Map<Id, Datetime> scheduledDateByApp = new Map<Id, Datetime>();
    Map<Id, List<InterviewerReview>> reviewsByApp = new Map<Id, List<InterviewerReview>>();

    Map<String, Integer> statusPriority = new Map<String, Integer>{
      'Completed' => 1,
      'Scheduled' => 2,
      'Pending_Scheduling' => 3,
      'Cancelled' => 4,
      'No_Show' => 5
    };

    for (Interview__c iv : interviews) {
      Id appId = iv.Job_Application__c;
      Boolean isCurrentStage = iv.Interview_Stage__c == currentStageId;

      // Table-level aggregates scoped to current stage only
      if (isCurrentStage) {
        totalByApp.put(appId, (totalByApp.get(appId) ?? 0) + 1);
        if (iv.Status__c == 'Completed') {
          completedByApp.put(appId, (completedByApp.get(appId) ?? 0) + 1);
        }
        if (iv.Score__c != null) {
          scoreSumByApp.put(
            appId,
            (scoreSumByApp.get(appId) ?? 0) + iv.Score__c
          );
          scoredByApp.put(appId, (scoredByApp.get(appId) ?? 0) + 1);
        }
        String prev = worstStatusByApp.get(appId);
        Integer prevP = prev != null ? (statusPriority.get(prev) ?? 99) : 99;
        Integer currP = statusPriority.get(iv.Status__c) ?? 99;
        if (currP < prevP) {
          worstStatusByApp.put(appId, iv.Status__c);
        }
        if (iv.Invitation_Sent__c) {
          invitedByApp.put(appId, true);
        }
        if (iv.Status__c == 'Scheduled' && iv.Scheduled_DateTime__c != null) {
          Datetime existing = scheduledDateByApp.get(appId);
          if (existing == null || iv.Scheduled_DateTime__c < existing) {
            scheduledDateByApp.put(appId, iv.Scheduled_DateTime__c);
          }
        }
      }

      // All-stage reviews for the expanded detail panel
      if (!reviewsByApp.containsKey(appId)) {
        reviewsByApp.put(appId, new List<InterviewerReview>());
      }
      InterviewerReview review = new InterviewerReview();
      review.interviewerName = iv.Interviewer__r?.Name ?? 'Not assigned yet';
      review.score = iv.Score__c;
      review.status = iv.Status__c;
      review.recommendation = iv.Recommendation__c;
      review.notes = iv.Notes__c;
      review.stageName = stageNameById.get(iv.Interview_Stage__c) ??
        'Unknown Stage';
      reviewsByApp.get(appId).add(review);
    }

    for (CandidateCard card : cards) {
      Id appId = card.applicationId;
      card.interviewsTotal = totalByApp.get(appId) ?? 0;
      card.interviewsCompleted = completedByApp.get(appId) ?? 0;

      if (card.interviewsTotal == 0) {
        card.interviewStatus = 'No Interview';
      } else if (card.interviewsCompleted == card.interviewsTotal) {
        card.interviewStatus = 'Completed';
      } else {
        card.interviewStatus = worstStatusByApp.get(appId) ??
          'Pending_Scheduling';
      }

      // Compute avg score from completed interviews
      Integer scored = scoredByApp.get(appId) ?? 0;
      if (scored > 0) {
        card.interviewScore = (scoreSumByApp.get(appId) / scored).setScale(2);
      }

      card.invitationSent =
        invitedByApp.containsKey(appId) && invitedByApp.get(appId);
      card.scheduledDateTime = scheduledDateByApp.get(appId);
      card.interviewerReviews = reviewsByApp.get(appId) ??
        new List<InterviewerReview>();
    }
  }

  // Candidate-facing self-scheduling page on the Experience Cloud portal.
  private static final String SCHEDULING_BASE_URL = 'https://oreitalent--dev.sandbox.my.site.com/talentforce/self-scheduling';

  @AuraEnabled
  public static void markInvitationSent(Id applicationId, Id stageId) {
    List<Interview__c> interviews = [
      SELECT
        Id,
        Job_Application__c,
        Job_Application__r.Job_Position__r.Title__c,
        Interview_Stage__r.Name,
        Job_Application__r.Candidate__r.FirstName__c,
        Job_Application__r.Candidate__r.LastName__c,
        Job_Application__r.Candidate__r.Email__c
      FROM Interview__c
      WHERE
        Job_Application__c = :applicationId
        AND Interview_Stage__c = :stageId
      LIMIT 1
    ];
    if (interviews.isEmpty()) {
      throw new AuraHandledException(
        'No interview found for this candidate at this stage.'
      );
    }

    // Send the invitation email first; if it fails the whole transaction rolls
    // back so Invitation_Sent__c never reports a send that didn't happen.
    sendSchedulingInvitation(interviews[0]);

    interviews[0].Invitation_Sent__c = true;
    update interviews[0];
  }

  /**
   * Emails the candidate inviting them to self-schedule their interview for this stage.
   * Sends from an Org-Wide Email Address when one is configured, otherwise the running user.
   */
  private static void sendSchedulingInvitation(Interview__c iv) {
    String candidateEmail = iv.Job_Application__r?.Candidate__r?.Email__c;
    if (String.isBlank(candidateEmail)) {
      throw new AuraHandledException(
        'Cannot send the invitation: the candidate has no email address on file.'
      );
    }

    String fn = iv.Job_Application__r?.Candidate__r?.FirstName__c;
    String greeting = String.isNotBlank(fn) ? 'Hi ' + fn + ',' : 'Hello,';
    String jobTitle = iv.Job_Application__r?.Job_Position__r?.Title__c;
    String positionLabel = String.isNotBlank(jobTitle)
      ? ' for the ' + jobTitle + ' position'
      : '';
    String stageName = iv.Interview_Stage__r != null
      ? iv.Interview_Stage__r.Name
      : null;
    String stageLabel = String.isNotBlank(stageName)
      ? ' (' + stageName + ')'
      : '';

    String schedulingUrl =
      SCHEDULING_BASE_URL +
      '?applicationId=' +
      iv.Job_Application__c;

    String subject =
      'You\'re invited to schedule your interview' +
      (String.isNotBlank(jobTitle) ? ' — ' + jobTitle : '');

    String htmlBody =
      '<p>' +
      greeting +
      '</p>' +
      '<p>Congratulations! You\'ve been invited to the next interview stage' +
      stageLabel +
      positionLabel +
      '.</p>' +
      '<p>Please choose a time that works for you using the link below:</p>' +
      '<p><a href="' +
      schedulingUrl +
      '">Schedule your interview</a></p>' +
      '<p>If the link doesn\'t open, copy and paste this URL into your browser:<br/>' +
      schedulingUrl +
      '</p>' +
      '<p>We look forward to speaking with you.</p>';

    String plainBody =
      greeting +
      '\n\n' +
      'Congratulations! You\'ve been invited to the next interview stage' +
      stageLabel +
      positionLabel +
      '.\n\n' +
      'Please choose a time that works for you here:\n' +
      schedulingUrl +
      '\n\n' +
      'We look forward to speaking with you.';

    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setToAddresses(new List<String>{ candidateEmail });
    email.setSubject(subject);
    email.setHtmlBody(htmlBody);
    email.setPlainTextBody(plainBody);
    email.setSaveAsActivity(false);

    List<OrgWideEmailAddress> owea = [
      SELECT Id
      FROM OrgWideEmailAddress
      LIMIT 1
    ];
    if (!owea.isEmpty()) {
      email.setOrgWideEmailAddressId(owea[0].Id);
    }

    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ email }
    );
    if (results != null && !results.isEmpty() && !results[0].isSuccess()) {
      String err = results[0].getErrors() != null &&
        !results[0].getErrors().isEmpty()
        ? results[0].getErrors()[0].getMessage()
        : 'Unknown error';
      throw new AuraHandledException(
        'Failed to send the invitation email: ' + err
      );
    }
  }

  private static Boolean isFirstStage(Id jobPositionId, Decimal stageNumber) {
    AggregateResult[] agg = [
      SELECT MIN(Stage_Number__c) minNum
      FROM Interview_Stage__c
      WHERE Job_Position__c = :jobPositionId
    ];
    Decimal minNum = (Decimal) agg[0].get('minNum');
    return minNum != null && minNum == stageNumber;
  }

  private static Id getPreviousStageId(
    Id jobPositionId,
    Decimal currentStageNumber
  ) {
    List<Interview_Stage__c> prev = [
      SELECT Id
      FROM Interview_Stage__c
      WHERE
        Job_Position__c = :jobPositionId
        AND Stage_Number__c < :currentStageNumber
      ORDER BY Stage_Number__c DESC
      LIMIT 1
    ];
    return prev.isEmpty() ? null : prev[0].Id;
  }

  private static String buildInitials(String firstName, String lastName) {
    String fi = (firstName != null &&
      firstName.length() > 0)
      ? firstName.substring(0, 1)
      : '';
    String li = (lastName != null &&
      lastName.length() > 0)
      ? lastName.substring(0, 1)
      : '';
    String result = (fi + li).toUpperCase();
    return String.isBlank(result) ? '?' : result;
  }
}
