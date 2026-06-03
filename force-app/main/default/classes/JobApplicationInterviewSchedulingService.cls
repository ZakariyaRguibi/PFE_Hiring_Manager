/**
 * @description Creates pending self-scheduling interviews when applications enter
 *              the Interview stage or move between interview stages.
 */
public without sharing class JobApplicationInterviewSchedulingService {
  private static final String APP_STAGE_INTERVIEW = 'Interview';
  private static final String INTERVIEW_STATUS_PENDING = 'Pending_Scheduling';

  private static final Set<String> ACTIVE_INTERVIEW_STATUSES = new Set<String>{
    'Pending_Scheduling',
    'Scheduled'
  };

  public static final Integer SCHEDULING_WINDOW_DAYS = 7;
  public static final Integer MINIMUM_INTERVIEW_OFFSET_DAYS = 3;

  private static Boolean isRunning = false;
  private static Map<String, Boolean> validSlotCache = new Map<String, Boolean>();

  public static void prepareCurrentInterviewStage(
    List<Job_Application__c> newList,
    Map<Id, Job_Application__c> oldMap
  ) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    Set<Id> jobPositionIds = new Set<Id>();

    for (Job_Application__c app : newList) {
      Job_Application__c oldApp = oldMap != null ? oldMap.get(app.Id) : null;

      Boolean enteringInterview =
        app.Stage__c == APP_STAGE_INTERVIEW &&
        (oldApp == null ||
        oldApp.Stage__c != APP_STAGE_INTERVIEW);

      if (
        enteringInterview &&
        app.Current_Interview_Stage__c == null &&
        app.Job_Position__c != null
      ) {
        jobPositionIds.add(app.Job_Position__c);
      }
    }

    if (jobPositionIds.isEmpty()) {
      return;
    }

    Map<Id, Id> jobToFirstStage = findFirstStageByJob(jobPositionIds);

    for (Job_Application__c app : newList) {
      if (
        app.Stage__c == APP_STAGE_INTERVIEW &&
        app.Current_Interview_Stage__c == null &&
        app.Job_Position__c != null &&
        jobToFirstStage.containsKey(app.Job_Position__c)
      ) {
        app.Current_Interview_Stage__c = jobToFirstStage.get(
          app.Job_Position__c
        );
      }
    }
  }

  public static void handleApplicationAfterSave(
    List<Job_Application__c> newList,
    Map<Id, Job_Application__c> oldMap
  ) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    Set<Id> applicationIds = new Set<Id>();

    for (Job_Application__c app : newList) {
      Job_Application__c oldApp = oldMap != null ? oldMap.get(app.Id) : null;

      Boolean enteredInterviewStage =
        app.Stage__c == APP_STAGE_INTERVIEW &&
        (oldApp == null ||
        oldApp.Stage__c != APP_STAGE_INTERVIEW);

      Boolean currentStageChangedWhileInterview =
        app.Stage__c == APP_STAGE_INTERVIEW &&
        oldApp != null &&
        oldApp.Stage__c == APP_STAGE_INTERVIEW &&
        app.Current_Interview_Stage__c != null &&
        app.Current_Interview_Stage__c != oldApp.Current_Interview_Stage__c;

      if (enteredInterviewStage || currentStageChangedWhileInterview) {
        applicationIds.add(app.Id);
      }
    }

    if (!applicationIds.isEmpty()) {
      createPendingSchedulingInterviews(applicationIds);
    }
  }

  public static void handleApplicationsMovedToInterview(
    List<Job_Application__c> newList,
    Map<Id, Job_Application__c> oldMap
  ) {
    handleApplicationAfterSave(newList, oldMap);
  }

  public static void createPendingSchedulingInterviews(Set<Id> applicationIds) {
    if (isRunning == true) {
      return;
    }

    if (applicationIds == null || applicationIds.isEmpty()) {
      return;
    }

    isRunning = true;

    try {
      List<Job_Application__c> applications = [
        SELECT Id, Stage__c, Job_Position__c, Current_Interview_Stage__c
        FROM Job_Application__c
        WHERE Id IN :applicationIds
        WITH SYSTEM_MODE
      ];

      if (applications.isEmpty()) {
        return;
      }

      Map<Id, Id> appToStageId = resolveStageForApplications(applications);

      if (appToStageId.isEmpty()) {
        return;
      }

      Set<Id> stageIds = new Set<Id>(appToStageId.values());

      Set<Id> applicationsWithExistingInterview = findApplicationsWithActiveInterview(
        appToStageId.keySet(),
        stageIds
      );

      Set<Id> stagesWithTeamMembers = findStagesWithTeamMembers(stageIds);

      Datetime nowDt = System.now();
      Datetime schedulingDeadline = nowDt.addDays(SCHEDULING_WINDOW_DAYS);
      Datetime earliestAllowedSlotStart = nowDt.addDays(
        MINIMUM_INTERVIEW_OFFSET_DAYS
      );

      Map<Id, Boolean> stageHasValidCandidateSlot = new Map<Id, Boolean>();

      for (Id stageId : stageIds) {
        if (!stagesWithTeamMembers.contains(stageId)) {
          stageHasValidCandidateSlot.put(stageId, false);
          continue;
        }

        stageHasValidCandidateSlot.put(
          stageId,
          hasValidCandidateSlot(
            stageId,
            earliestAllowedSlotStart,
            schedulingDeadline
          )
        );
      }

      List<Interview__c> interviewsToInsert = new List<Interview__c>();

      for (Job_Application__c app : applications) {
        if (app.Stage__c != APP_STAGE_INTERVIEW) {
          continue;
        }

        Id stageId = appToStageId.get(app.Id);

        if (stageId == null) {
          continue;
        }

        if (applicationsWithExistingInterview.contains(app.Id)) {
          continue;
        }

        if (!stagesWithTeamMembers.contains(stageId)) {
          continue;
        }

        if (stageHasValidCandidateSlot.get(stageId) != true) {
          continue;
        }

        interviewsToInsert.add(
          new Interview__c(
            Job_Application__c = app.Id,
            Interview_Stage__c = stageId,
            Status__c = INTERVIEW_STATUS_PENDING,
            Interviewer__c = null,
            Scheduled_DateTime__c = null,
            Scheduling_Deadline__c = schedulingDeadline,
            Candidate_Tried_To_Schedule__c = false
          )
        );
      }

      if (!interviewsToInsert.isEmpty()) {
        AvailabilitySlotTriggerHandler.skipSchedulingRetry = true;

        try {
          insert as system interviewsToInsert;
        } finally {
          AvailabilitySlotTriggerHandler.skipSchedulingRetry = false;
        }
      }
    } finally {
      isRunning = false;
    }
  }

  private static Map<Id, Id> resolveStageForApplications(
    List<Job_Application__c> applications
  ) {
    Map<Id, Id> appToStageId = new Map<Id, Id>();

    for (Job_Application__c app : applications) {
      if (
        app.Stage__c == APP_STAGE_INTERVIEW &&
        app.Current_Interview_Stage__c != null
      ) {
        appToStageId.put(app.Id, app.Current_Interview_Stage__c);
      }
    }

    return appToStageId;
  }

  private static Map<Id, Id> findFirstStageByJob(Set<Id> jobPositionIds) {
    Map<Id, Id> jobToFirstStage = new Map<Id, Id>();

    if (jobPositionIds == null || jobPositionIds.isEmpty()) {
      return jobToFirstStage;
    }

    for (Interview_Stage__c stage : [
      SELECT Id, Job_Position__c, Stage_Number__c
      FROM Interview_Stage__c
      WHERE Job_Position__c IN :jobPositionIds
      WITH SYSTEM_MODE
      ORDER BY Job_Position__c, Stage_Number__c ASC
    ]) {
      if (!jobToFirstStage.containsKey(stage.Job_Position__c)) {
        jobToFirstStage.put(stage.Job_Position__c, stage.Id);
      }
    }

    return jobToFirstStage;
  }

  private static Set<Id> findApplicationsWithActiveInterview(
    Set<Id> appIds,
    Set<Id> stageIds
  ) {
    Set<Id> result = new Set<Id>();

    if (
      appIds == null ||
      appIds.isEmpty() ||
      stageIds == null ||
      stageIds.isEmpty()
    ) {
      return result;
    }

    for (Interview__c interviewRecord : [
      SELECT Id, Job_Application__c
      FROM Interview__c
      WHERE
        Job_Application__c IN :appIds
        AND Interview_Stage__c IN :stageIds
        AND Status__c IN :ACTIVE_INTERVIEW_STATUSES
      WITH SYSTEM_MODE
    ]) {
      if (interviewRecord.Job_Application__c != null) {
        result.add(interviewRecord.Job_Application__c);
      }
    }

    return result;
  }

  private static Set<Id> findStagesWithTeamMembers(Set<Id> stageIds) {
    Set<Id> result = new Set<Id>();

    if (stageIds == null || stageIds.isEmpty()) {
      return result;
    }

    for (Interview_Stage_Team_Member__c member : [
      SELECT Interview_Stage__c
      FROM Interview_Stage_Team_Member__c
      WHERE Interview_Stage__c IN :stageIds
      WITH SYSTEM_MODE
    ]) {
      if (member.Interview_Stage__c != null) {
        result.add(member.Interview_Stage__c);
      }
    }

    return result;
  }

  public static Boolean hasValidCandidateSlot(
    Id stageId,
    Datetime earliestAllowedSlotStart,
    Datetime schedulingDeadline
  ) {
    return hasValidCandidateSlot(
      stageId,
      earliestAllowedSlotStart,
      schedulingDeadline,
      false
    );
  }

  public static Boolean hasValidCandidateSlot(
    Id stageId,
    Datetime earliestAllowedSlotStart,
    Datetime schedulingDeadline,
    Boolean includePastSlots
  ) {
    if (stageId == null) {
      return false;
    }

    String cacheKey =
      String.valueOf(stageId) +
      '|' +
      String.valueOf(includePastSlots == true);

    if (validSlotCache.containsKey(cacheKey)) {
      return validSlotCache.get(cacheKey);
    }

    List<Interview_Stage_Team_Member__c> members = [
      SELECT Interviewer__c
      FROM Interview_Stage_Team_Member__c
      WHERE Interview_Stage__c = :stageId
      WITH SYSTEM_MODE
    ];

    if (members.isEmpty()) {
      validSlotCache.put(cacheKey, false);
      return false;
    }

    Set<Id> interviewerIds = new Set<Id>();

    for (Interview_Stage_Team_Member__c member : members) {
      if (member.Interviewer__c != null) {
        interviewerIds.add(member.Interviewer__c);
      }
    }

    if (interviewerIds.isEmpty()) {
      validSlotCache.put(cacheKey, false);
      return false;
    }

    Integer slotCount = [
      SELECT COUNT()
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Is_Blocked__c = FALSE
        AND Is_Booked__c != TRUE
        AND Deactivated_Date__c = NULL
        AND Start_DateTime__c != NULL
        AND End_DateTime__c != NULL
      WITH SYSTEM_MODE
    ];

    Boolean result = slotCount > 0;

    validSlotCache.put(cacheKey, result);

    return result;
  }

  public static void handleAvailabilityAfterSave(
    List<Availability_Slot__c> newList,
    Map<Id, Availability_Slot__c> oldMap
  ) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    Set<Id> interviewerIds = new Set<Id>();

    for (Availability_Slot__c slot : newList) {
      if (!isPotentiallyUsableAvailability(slot)) {
        continue;
      }

      if (oldMap != null) {
        Availability_Slot__c oldSlot = oldMap.get(slot.Id);

        if (oldSlot != null && !becameUsableOrChanged(slot, oldSlot)) {
          continue;
        }
      }

      interviewerIds.add(slot.Interviewer__c);
    }

    if (interviewerIds.isEmpty()) {
      return;
    }

    Set<Id> stageIds = new Set<Id>();

    for (Interview_Stage_Team_Member__c member : [
      SELECT Interview_Stage__c
      FROM Interview_Stage_Team_Member__c
      WHERE Interviewer__c IN :interviewerIds
      WITH SYSTEM_MODE
    ]) {
      if (member.Interview_Stage__c != null) {
        stageIds.add(member.Interview_Stage__c);
      }
    }

    if (stageIds.isEmpty()) {
      return;
    }

    Set<Id> waitingApplicationIds = new Set<Id>();

    for (Job_Application__c app : [
      SELECT Id
      FROM Job_Application__c
      WHERE
        Stage__c = :APP_STAGE_INTERVIEW
        AND Current_Interview_Stage__c IN :stageIds
      WITH SYSTEM_MODE
    ]) {
      waitingApplicationIds.add(app.Id);
    }

    if (!waitingApplicationIds.isEmpty()) {
      clearAvailabilityCache();
      createPendingSchedulingInterviews(waitingApplicationIds);
    }
  }

  public static void handleTeamMemberAfterSave(
    List<Interview_Stage_Team_Member__c> newList,
    Map<Id, Interview_Stage_Team_Member__c> oldMap
  ) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    Set<Id> affectedStageIds = new Set<Id>();

    for (Interview_Stage_Team_Member__c member : newList) {
      if (member.Interview_Stage__c == null || member.Interviewer__c == null) {
        continue;
      }

      if (oldMap != null) {
        Interview_Stage_Team_Member__c oldMember = oldMap.get(member.Id);

        if (
          oldMember != null &&
          oldMember.Interview_Stage__c == member.Interview_Stage__c &&
          oldMember.Interviewer__c == member.Interviewer__c
        ) {
          continue;
        }
      }

      affectedStageIds.add(member.Interview_Stage__c);
    }

    if (affectedStageIds.isEmpty()) {
      return;
    }

    Set<Id> waitingApplicationIds = new Set<Id>();

    for (Job_Application__c app : [
      SELECT Id
      FROM Job_Application__c
      WHERE
        Stage__c = :APP_STAGE_INTERVIEW
        AND Current_Interview_Stage__c IN :affectedStageIds
      WITH SYSTEM_MODE
    ]) {
      waitingApplicationIds.add(app.Id);
    }

    if (!waitingApplicationIds.isEmpty()) {
      clearAvailabilityCache();
      createPendingSchedulingInterviews(waitingApplicationIds);
    }
  }

  private static Boolean isPotentiallyUsableAvailability(
    Availability_Slot__c slot
  ) {
    return slot != null &&
      slot.Interviewer__c != null &&
      slot.Is_Blocked__c == false &&
      slot.Is_Booked__c != true &&
      slot.Deactivated_Date__c == null &&
      slot.Start_DateTime__c != null &&
      slot.End_DateTime__c != null;
  }

  private static Boolean becameUsableOrChanged(
    Availability_Slot__c slot,
    Availability_Slot__c oldSlot
  ) {
    return oldSlot.Interviewer__c != slot.Interviewer__c ||
      oldSlot.Is_Recurring__c != slot.Is_Recurring__c ||
      oldSlot.Is_Blocked__c != slot.Is_Blocked__c ||
      oldSlot.Is_Booked__c != slot.Is_Booked__c ||
      oldSlot.Deactivated_Date__c != slot.Deactivated_Date__c ||
      oldSlot.Day_Of_Week__c != slot.Day_Of_Week__c ||
      oldSlot.Start_DateTime__c != slot.Start_DateTime__c ||
      oldSlot.End_DateTime__c != slot.End_DateTime__c;
  }

  private static void clearAvailabilityCache() {
    validSlotCache.clear();
  }

  private static Date mondayOf(Date d) {
    DateTime dt = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    String dayName = dt.format('EEEE');

    Map<String, Integer> backDays = new Map<String, Integer>{
      'Monday' => 0,
      'Tuesday' => 1,
      'Wednesday' => 2,
      'Thursday' => 3,
      'Friday' => 4,
      'Saturday' => 5,
      'Sunday' => 6
    };

    Integer back = backDays.containsKey(dayName) ? backDays.get(dayName) : 0;
    return d.addDays(-back);
  }
}
