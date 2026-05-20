/**
 * @description Provides candidate-side interview self-scheduling actions for the portal.
 * The candidate selects a datetime only; the backend assigns the least-loaded eligible interviewer.
 */
public without sharing class CandidateInterviewSchedulerCtrl {
  private static final String STATUS_PENDING = 'Pending_Scheduling';
  private static final String STATUS_SCHEDULED = 'Scheduled';
  private static final String ISSUE_NO_AVAILABLE_SLOTS = 'No_Available_Slots';
  private static final String ISSUE_SLOT_BECAME_UNAVAILABLE = 'Slot_Became_Unavailable';
  private static final Set<String> LOAD_STATUSES = new Set<String>{
    'Scheduled',
    'Completed'
  };

  public class PendingInterviewDTO {
    @AuraEnabled
    public Id interviewId;
    @AuraEnabled
    public String interviewName;
    @AuraEnabled
    public String jobTitle;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public String interviewerName;
    @AuraEnabled
    public Datetime schedulingDeadline;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime scheduledDateTime;
    @AuraEnabled
    public Datetime earliestAllowedSlotStart;
    @AuraEnabled
    public Boolean candidateTriedToSchedule;
    @AuraEnabled
    public Datetime candidateTriedToScheduleAt;
    @AuraEnabled
    public String schedulingIssueReason;
  }

  private class CandidateAvailabilityWindow {
    Id availabilitySlotId;
    Id interviewerId;
    String interviewerName;
    Datetime startDateTime;
    Datetime endDateTime;
    Boolean isRecurring;
    String dayOfWeek;
  }

  @AuraEnabled(cacheable=true)
  public static PendingInterviewDTO getPendingInterview() {
    List<Interview__c> interviews = [
      SELECT
        Id,
        Name,
        CreatedDate,
        Status__c,
        Scheduled_DateTime__c,
        Scheduling_Deadline__c,
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c,
        Interviewer__r.Name,
        Interview_Stage__r.Name,
        Job_Application__r.Job_Position__r.Title__c,
        Job_Application__r.Candidate__r.User__c
      FROM Interview__c
      WHERE
        Job_Application__r.Candidate__r.User__c = :UserInfo.getUserId()
        AND Status__c = :STATUS_PENDING
        AND Scheduled_DateTime__c = NULL
      WITH SYSTEM_MODE
      ORDER BY Scheduling_Deadline__c ASC, CreatedDate ASC
      LIMIT 1
    ];

    if (interviews.isEmpty()) {
      return null;
    }

    Interview__c interviewRecord = interviews[0];

    PendingInterviewDTO dto = new PendingInterviewDTO();
    dto.interviewId = interviewRecord.Id;
    dto.interviewName = interviewRecord.Name;
    dto.status = interviewRecord.Status__c;
    dto.scheduledDateTime = interviewRecord.Scheduled_DateTime__c;
    dto.schedulingDeadline = interviewRecord.Scheduling_Deadline__c;
    dto.earliestAllowedSlotStart = getEarliestAllowedSlotStart(interviewRecord);
    dto.candidateTriedToSchedule = interviewRecord.Candidate_Tried_To_Schedule__c;
    dto.candidateTriedToScheduleAt = interviewRecord.Candidate_Tried_To_Schedule_At__c;
    dto.schedulingIssueReason = interviewRecord.Scheduling_Issue_Reason__c;
    dto.interviewerName = interviewRecord.Interviewer__r != null
      ? interviewRecord.Interviewer__r.Name
      : null;
    dto.stageName = interviewRecord.Interview_Stage__r != null
      ? interviewRecord.Interview_Stage__r.Name
      : null;
    dto.jobTitle = interviewRecord.Job_Application__r != null &&
      interviewRecord.Job_Application__r.Job_Position__r != null
      ? interviewRecord.Job_Application__r.Job_Position__r.Title__c
      : null;

    return dto;
  }

  @AuraEnabled(cacheable=false)
  public static List<AvailabilitySlotService.TimeSlotDTO> getAvailableSlots(
    Id interviewId,
    String weekStart
  ) {
    Interview__c interviewRecord = loadCandidateOwnedInterview(interviewId);
    validateInterviewCanBeScheduled(interviewRecord);

    List<AvailabilitySlotService.TimeSlotDTO> stageSlots = AvailabilitySlotService.getAvailableSlotsForStage(
      interviewRecord.Interview_Stage__c,
      weekStart
    );

    List<AvailabilitySlotService.TimeSlotDTO> validSlots = filterSlotsForCandidateAndDeadline(
      interviewRecord,
      stageSlots
    );

    return mergeSlotsByDateTime(validSlots);
  }

  @AuraEnabled
  public static void markCandidateTriedToSchedule(Id interviewId) {
    Interview__c interviewRecord = loadCandidateOwnedInterview(interviewId);
    validateInterviewCanBeScheduled(interviewRecord);

    update as system new Interview__c(
      Id = interviewRecord.Id,
      Candidate_Tried_To_Schedule__c = true,
      Candidate_Tried_To_Schedule_At__c = System.now(),
      Scheduling_Issue_Reason__c = null
    );
  }

  @AuraEnabled
  public static void recordNoAvailableSlots(Id interviewId) {
    recordSchedulingIssue(interviewId, ISSUE_NO_AVAILABLE_SLOTS, true);
  }

  @AuraEnabled
  public static void recordSlotBecameUnavailable(Id interviewId) {
    recordSchedulingIssue(interviewId, ISSUE_SLOT_BECAME_UNAVAILABLE, false);
  }

  @AuraEnabled
  public static void recordSchedulingIssue(Id interviewId, String issueReason) {
    recordSchedulingIssue(
      interviewId,
      issueReason,
      issueReason == ISSUE_NO_AVAILABLE_SLOTS
    );
  }

  @AuraEnabled
  public static void scheduleInterview(
    Id interviewId,
    String selectedStartDateTime
  ) {
    if (interviewId == null) {
      throw new AuraHandledException('Interview id is required.');
    }

    Datetime selectedStart = parseClientDateTime(selectedStartDateTime);

    Interview__c interviewRecord = [
      SELECT
        Id,
        CreatedDate,
        Status__c,
        Scheduled_DateTime__c,
        Scheduling_Deadline__c,
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c,
        Interviewer__c,
        Availability_Slot__c,
        Interview_Stage__c,
        Interview_Stage__r.Duration_Minutes__c,
        Job_Application__c,
        Job_Application__r.Candidate__c,
        Job_Application__r.Candidate__r.User__c,
        Job_Application__r.Job_Position__c
      FROM Interview__c
      WHERE Id = :interviewId
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];

    validateCandidateOwnership(interviewRecord);
    validateInterviewCanBeScheduled(interviewRecord);

    Integer durationMinutes = getDurationMinutes(interviewRecord);
    Datetime selectedEnd = selectedStart.addMinutes(durationMinutes);

    Datetime earliestAllowedSlotStart = getEarliestAllowedSlotStart(
      interviewRecord
    );

    if (selectedStart < earliestAllowedSlotStart) {
      throw new AuraHandledException(
        'You can only choose an interview slot after the minimum preparation period.'
      );
    }

    if (selectedStart > interviewRecord.Scheduling_Deadline__c) {
      throw new AuraHandledException(
        'This slot is after the scheduling deadline.'
      );
    }

    validateCandidateHasNoOverlappingInterview(
      interviewRecord.Job_Application__r.Candidate__c,
      interviewRecord.Id,
      selectedStart,
      selectedEnd
    );

    List<CandidateAvailabilityWindow> matchingWindows = findCandidateAvailabilityWindows(
      interviewRecord,
      selectedStart,
      selectedEnd
    );

    if (matchingWindows.isEmpty()) {
      throw new AuraHandledException(
        'This slot is no longer available. Please choose another slot.'
      );
    }

    CandidateAvailabilityWindow selectedWindow = chooseLeastLoadedAvailabilityWindow(
      interviewRecord,
      matchingWindows,
      selectedStart,
      selectedEnd
    );

    if (selectedWindow == null || selectedWindow.interviewerId == null) {
      throw new AuraHandledException(
        'No interviewer is available anymore for this slot. Please choose another slot.'
      );
    }

    Id bookedAvailabilitySlotId;

    if (selectedWindow.isRecurring == true) {
      bookedAvailabilitySlotId = createBookedAvailabilitySlot(
        interviewRecord,
        selectedWindow,
        selectedStart,
        selectedEnd
      );
    } else {
      Availability_Slot__c existingSlot = [
        SELECT Id, Is_Booked__c, Booked_Interview__c
        FROM Availability_Slot__c
        WHERE Id = :selectedWindow.availabilitySlotId
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];

      existingSlot.Is_Booked__c = true;
      existingSlot.Booked_Interview__c = interviewRecord.Id;

      update as system existingSlot;

      bookedAvailabilitySlotId = existingSlot.Id;
    }

    interviewRecord.Interviewer__c = selectedWindow.interviewerId;
    interviewRecord.Status__c = STATUS_SCHEDULED;
    interviewRecord.Scheduled_DateTime__c = selectedStart;
    interviewRecord.Availability_Slot__c = bookedAvailabilitySlotId;
    interviewRecord.Candidate_Tried_To_Schedule__c = true;
    interviewRecord.Candidate_Tried_To_Schedule_At__c = System.now();
    interviewRecord.Scheduling_Issue_Reason__c = null;

    update as system interviewRecord;
  }

  private static void recordSchedulingIssue(
    Id interviewId,
    String issueReason,
    Boolean markAsAttempt
  ) {
    if (String.isBlank(issueReason)) {
      throw new AuraHandledException('Scheduling issue reason is required.');
    }

    if (
      issueReason != ISSUE_NO_AVAILABLE_SLOTS &&
      issueReason != ISSUE_SLOT_BECAME_UNAVAILABLE
    ) {
      throw new AuraHandledException('Unsupported scheduling issue reason.');
    }

    Interview__c interviewRecord = loadCandidateOwnedInterview(interviewId);
    validateInterviewCanBeScheduled(interviewRecord);

    Interview__c updateRecord = new Interview__c(
      Id = interviewRecord.Id,
      Scheduling_Issue_Reason__c = issueReason
    );

    if (markAsAttempt == true) {
      updateRecord.Candidate_Tried_To_Schedule__c = true;
      updateRecord.Candidate_Tried_To_Schedule_At__c = System.now();
    }

    update as system updateRecord;
  }

  private static Interview__c loadCandidateOwnedInterview(Id interviewId) {
    if (interviewId == null) {
      throw new AuraHandledException('Interview id is required.');
    }

    List<Interview__c> interviews = [
      SELECT
        Id,
        CreatedDate,
        Status__c,
        Scheduled_DateTime__c,
        Scheduling_Deadline__c,
        Candidate_Tried_To_Schedule__c,
        Candidate_Tried_To_Schedule_At__c,
        Scheduling_Issue_Reason__c,
        Interviewer__c,
        Interview_Stage__c,
        Interview_Stage__r.Duration_Minutes__c,
        Job_Application__c,
        Job_Application__r.Candidate__c,
        Job_Application__r.Candidate__r.User__c,
        Job_Application__r.Job_Position__c
      FROM Interview__c
      WHERE
        Id = :interviewId
        AND Job_Application__r.Candidate__r.User__c = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (interviews.isEmpty()) {
      throw new AuraHandledException('Interview not found or access denied.');
    }

    return interviews[0];
  }

  private static void validateCandidateOwnership(Interview__c interviewRecord) {
    if (
      interviewRecord.Job_Application__r == null ||
      interviewRecord.Job_Application__r.Candidate__r == null ||
      interviewRecord.Job_Application__r.Candidate__r.User__c !=
      UserInfo.getUserId()
    ) {
      throw new AuraHandledException(
        'You are not allowed to schedule this interview.'
      );
    }
  }

  private static void validateInterviewCanBeScheduled(
    Interview__c interviewRecord
  ) {
    if (interviewRecord.Status__c != STATUS_PENDING) {
      throw new AuraHandledException(
        'This interview is not pending scheduling.'
      );
    }

    if (interviewRecord.Scheduled_DateTime__c != null) {
      throw new AuraHandledException('This interview is already scheduled.');
    }

    if (interviewRecord.Scheduling_Deadline__c == null) {
      throw new AuraHandledException(
        'No scheduling deadline is defined for this interview.'
      );
    }

    if (System.now() > interviewRecord.Scheduling_Deadline__c) {
      throw new AuraHandledException('The scheduling deadline has passed.');
    }
  }

  private static List<AvailabilitySlotService.TimeSlotDTO> filterSlotsForCandidateAndDeadline(
    Interview__c interviewRecord,
    List<AvailabilitySlotService.TimeSlotDTO> slots
  ) {
    List<AvailabilitySlotService.TimeSlotDTO> validSlots = new List<AvailabilitySlotService.TimeSlotDTO>();

    if (slots == null || slots.isEmpty()) {
      return validSlots;
    }

    Integer durationMinutes = getDurationMinutes(interviewRecord);
    Datetime earliestAllowedSlotStart = getEarliestAllowedSlotStart(
      interviewRecord
    );

    List<Datetime[]> candidateBusyIntervals = loadCandidateBusyIntervals(
      interviewRecord.Job_Application__r.Candidate__c,
      interviewRecord.Id,
      earliestAllowedSlotStart,
      interviewRecord.Scheduling_Deadline__c
    );

    for (AvailabilitySlotService.TimeSlotDTO slot : slots) {
      if (slot == null || slot.startDt == null || slot.endDt == null) {
        continue;
      }

      if (slot.startDt < earliestAllowedSlotStart) {
        continue;
      }

      if (slot.startDt > interviewRecord.Scheduling_Deadline__c) {
        continue;
      }

      Datetime expectedEnd = slot.startDt.addMinutes(durationMinutes);

      if (!sameInstant(slot.endDt, expectedEnd)) {
        continue;
      }

      if (overlapsAny(slot.startDt, slot.endDt, candidateBusyIntervals)) {
        continue;
      }

      validSlots.add(slot);
    }

    return validSlots;
  }

  private static Datetime getEarliestAllowedSlotStart(
    Interview__c interviewRecord
  ) {
    Datetime baseDateTime = interviewRecord.CreatedDate != null
      ? interviewRecord.CreatedDate
      : System.now();

    return baseDateTime.addDays(
      JobApplicationInterviewSchedulingService.MINIMUM_INTERVIEW_OFFSET_DAYS
    );
  }

  private static List<Datetime[]> loadCandidateBusyIntervals(
    Id candidateId,
    Id currentInterviewId,
    Datetime rangeStart,
    Datetime rangeEnd
  ) {
    List<Datetime[]> busyIntervals = new List<Datetime[]>();

    if (candidateId == null || rangeStart == null || rangeEnd == null) {
      return busyIntervals;
    }

    for (Interview__c existingInterview : [
      SELECT Id, Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
      FROM Interview__c
      WHERE
        Id != :currentInterviewId
        AND Job_Application__r.Candidate__c = :candidateId
        AND Status__c = :STATUS_SCHEDULED
        AND Scheduled_DateTime__c != NULL
        AND Scheduled_DateTime__c <= :rangeEnd
      WITH SYSTEM_MODE
    ]) {
      Integer existingDuration = existingInterview.Interview_Stage__r.Duration_Minutes__c !=
        null
        ? Integer.valueOf(
            existingInterview.Interview_Stage__r.Duration_Minutes__c
          )
        : 60;

      Datetime existingStart = existingInterview.Scheduled_DateTime__c;
      Datetime existingEnd = existingStart.addMinutes(existingDuration);

      if (existingEnd >= rangeStart) {
        busyIntervals.add(new List<Datetime>{ existingStart, existingEnd });
      }
    }

    return busyIntervals;
  }

  private static Boolean overlapsAny(
    Datetime candidateStart,
    Datetime candidateEnd,
    List<Datetime[]> busyIntervals
  ) {
    for (Datetime[] interval : busyIntervals) {
      if (candidateStart < interval[1] && candidateEnd > interval[0]) {
        return true;
      }
    }

    return false;
  }

  private static List<AvailabilitySlotService.TimeSlotDTO> mergeSlotsByDateTime(
    List<AvailabilitySlotService.TimeSlotDTO> rawSlots
  ) {
    Map<String, AvailabilitySlotService.TimeSlotDTO> byDateTime = new Map<String, AvailabilitySlotService.TimeSlotDTO>();

    for (AvailabilitySlotService.TimeSlotDTO rawSlot : rawSlots) {
      String key = buildSlotKey(rawSlot.startDt, rawSlot.endDt);

      if (!byDateTime.containsKey(key)) {
        AvailabilitySlotService.TimeSlotDTO publicSlot = new AvailabilitySlotService.TimeSlotDTO();

        publicSlot.label = rawSlot.label;
        publicSlot.startDt = rawSlot.startDt;
        publicSlot.endDt = rawSlot.endDt;
        publicSlot.interviewerId = null;
        publicSlot.interviewerName = null;
        publicSlot.availabilitySlotId = null;

        byDateTime.put(key, publicSlot);
      }
    }

    List<AvailabilitySlotService.TimeSlotDTO> mergedSlots = byDateTime.values();
    mergedSlots.sort(new PublicSlotComparator());

    return mergedSlots;
  }

  private static List<CandidateAvailabilityWindow> findCandidateAvailabilityWindows(
    Interview__c interviewRecord,
    Datetime selectedStart,
    Datetime selectedEnd
  ) {
    List<CandidateAvailabilityWindow> matchingWindows = new List<CandidateAvailabilityWindow>();

    if (
      interviewRecord == null ||
      interviewRecord.Interview_Stage__c == null ||
      selectedStart == null ||
      selectedEnd == null
    ) {
      return matchingWindows;
    }

    Set<Id> stageInterviewerIds = new Set<Id>();

    for (Interview_Stage_Team_Member__c member : [
      SELECT Interviewer__c
      FROM Interview_Stage_Team_Member__c
      WHERE
        Interview_Stage__c = :interviewRecord.Interview_Stage__c
        AND Interviewer__c != NULL
      WITH SYSTEM_MODE
    ]) {
      stageInterviewerIds.add(member.Interviewer__c);
    }

    if (stageInterviewerIds.isEmpty()) {
      return matchingWindows;
    }

    String selectedDayName = selectedStart.format('EEEE');
    Integer selectedStartMinute = minutesSinceMidnight(selectedStart.time());
    Integer selectedEndMinute = minutesSinceMidnight(selectedEnd.time());

    Datetime selectedDayStart = Datetime.newInstance(
      selectedStart.date(),
      Time.newInstance(0, 0, 0, 0)
    );

    Datetime selectedDayEnd = selectedDayStart.addDays(1);

    List<Availability_Slot__c> candidateWindows = [
      SELECT
        Id,
        Interviewer__c,
        Interviewer__r.Name,
        Start_DateTime__c,
        End_DateTime__c,
        Day_Of_Week__c,
        Is_Recurring__c,
        Is_Booked__c,
        Booked_Interview__c,
        Interview_Stage__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :stageInterviewerIds
        AND Is_Blocked__c = FALSE
        AND (Is_Booked__c = FALSE
        OR Is_Booked__c = NULL)
        AND Deactivated_Date__c = NULL
        AND (Interview_Stage__c = :interviewRecord.Interview_Stage__c
        OR Interview_Stage__c = NULL)
        AND ((Is_Recurring__c = TRUE
        AND Day_Of_Week__c = :selectedDayName)
        OR (Is_Recurring__c = FALSE
        AND Start_DateTime__c <= :selectedStart
        AND End_DateTime__c >= :selectedEnd))
      WITH SYSTEM_MODE
    ];

    Set<Id> interviewerIdsWithBookingConflict = findInterviewersWithBookedSlotConflict(
      stageInterviewerIds,
      selectedStart,
      selectedEnd,
      interviewRecord.Id
    );

    Set<Id> interviewerIdsWithInterviewConflict = findInterviewersWithInterviewConflict(
      stageInterviewerIds,
      selectedStart,
      selectedEnd,
      interviewRecord.Id
    );

    for (Availability_Slot__c candidateWindow : candidateWindows) {
      if (
        candidateWindow.Interviewer__c == null ||
        candidateWindow.Start_DateTime__c == null ||
        candidateWindow.End_DateTime__c == null ||
        interviewerIdsWithBookingConflict.contains(
          candidateWindow.Interviewer__c
        ) ||
        interviewerIdsWithInterviewConflict.contains(
          candidateWindow.Interviewer__c
        )
      ) {
        continue;
      }

      Boolean containsSlot = false;

      if (candidateWindow.Is_Recurring__c == true) {
        containsSlot =
          minutesSinceMidnight(candidateWindow.Start_DateTime__c.time()) <=
          selectedStartMinute &&
          minutesSinceMidnight(candidateWindow.End_DateTime__c.time()) >=
          selectedEndMinute;
      } else {
        containsSlot =
          candidateWindow.Start_DateTime__c <= selectedStart &&
          candidateWindow.End_DateTime__c >= selectedEnd;
      }

      if (!containsSlot) {
        continue;
      }

      CandidateAvailabilityWindow window = new CandidateAvailabilityWindow();
      window.availabilitySlotId = candidateWindow.Id;
      window.interviewerId = candidateWindow.Interviewer__c;
      window.interviewerName = candidateWindow.Interviewer__r != null
        ? candidateWindow.Interviewer__r.Name
        : null;
      window.startDateTime = candidateWindow.Start_DateTime__c;
      window.endDateTime = candidateWindow.End_DateTime__c;
      window.isRecurring = candidateWindow.Is_Recurring__c;
      window.dayOfWeek = candidateWindow.Day_Of_Week__c;

      matchingWindows.add(window);
    }

    return matchingWindows;
  }

  private static Set<Id> findInterviewersWithBookedSlotConflict(
    Set<Id> interviewerIds,
    Datetime selectedStart,
    Datetime selectedEnd,
    Id currentInterviewId
  ) {
    Set<Id> conflictingInterviewerIds = new Set<Id>();

    if (interviewerIds == null || interviewerIds.isEmpty()) {
      return conflictingInterviewerIds;
    }

    for (Availability_Slot__c existingBooking : [
      SELECT
        Id,
        Interviewer__c,
        Booked_Interview__c,
        Start_DateTime__c,
        End_DateTime__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Is_Booked__c = TRUE
        AND Deactivated_Date__c = NULL
        AND Start_DateTime__c < :selectedEnd
        AND End_DateTime__c > :selectedStart
      WITH SYSTEM_MODE
    ]) {
      if (existingBooking.Booked_Interview__c != currentInterviewId) {
        conflictingInterviewerIds.add(existingBooking.Interviewer__c);
      }
    }

    return conflictingInterviewerIds;
  }

  private static Set<Id> findInterviewersWithInterviewConflict(
    Set<Id> interviewerIds,
    Datetime selectedStart,
    Datetime selectedEnd,
    Id currentInterviewId
  ) {
    Set<Id> conflictingInterviewerIds = new Set<Id>();

    if (interviewerIds == null || interviewerIds.isEmpty()) {
      return conflictingInterviewerIds;
    }

    for (Interview__c existingInterview : [
      SELECT
        Id,
        Interviewer__c,
        Scheduled_DateTime__c,
        Interview_Stage__r.Duration_Minutes__c
      FROM Interview__c
      WHERE
        Id != :currentInterviewId
        AND Interviewer__c IN :interviewerIds
        AND Status__c = :STATUS_SCHEDULED
        AND Scheduled_DateTime__c != NULL
      WITH SYSTEM_MODE
    ]) {
      Integer existingDuration = existingInterview.Interview_Stage__r.Duration_Minutes__c !=
        null
        ? Integer.valueOf(
            existingInterview.Interview_Stage__r.Duration_Minutes__c
          )
        : 60;

      Datetime existingStart = existingInterview.Scheduled_DateTime__c;
      Datetime existingEnd = existingStart.addMinutes(existingDuration);

      if (existingStart < selectedEnd && existingEnd > selectedStart) {
        conflictingInterviewerIds.add(existingInterview.Interviewer__c);
      }
    }

    return conflictingInterviewerIds;
  }

  private static CandidateAvailabilityWindow chooseLeastLoadedAvailabilityWindow(
    Interview__c interviewRecord,
    List<CandidateAvailabilityWindow> matchingWindows,
    Datetime selectedStart,
    Datetime selectedEnd
  ) {
    if (matchingWindows == null || matchingWindows.isEmpty()) {
      return null;
    }

    Set<Id> eligibleInterviewerIds = new Set<Id>();
    Map<Id, CandidateAvailabilityWindow> windowByInterviewer = new Map<Id, CandidateAvailabilityWindow>();

    for (CandidateAvailabilityWindow window : matchingWindows) {
      if (window.interviewerId == null) {
        continue;
      }

      eligibleInterviewerIds.add(window.interviewerId);

      if (!windowByInterviewer.containsKey(window.interviewerId)) {
        windowByInterviewer.put(window.interviewerId, window);
      }
    }

    if (eligibleInterviewerIds.isEmpty()) {
      return null;
    }

    Map<Id, Integer> totalLoad = countInterviewerLoad(
      eligibleInterviewerIds,
      interviewRecord.Interview_Stage__c,
      interviewRecord.Job_Application__r.Job_Position__c,
      null
    );

    Map<Id, Integer> dayLoad = countInterviewerLoad(
      eligibleInterviewerIds,
      interviewRecord.Interview_Stage__c,
      interviewRecord.Job_Application__r.Job_Position__c,
      selectedStart.date()
    );

    Id bestInterviewerId;
    Integer bestTotalLoad;
    Integer bestDayLoad;
    String bestName;

    for (Id interviewerId : eligibleInterviewerIds) {
      Integer candidateTotalLoad = totalLoad.containsKey(interviewerId)
        ? totalLoad.get(interviewerId)
        : 0;
      Integer candidateDayLoad = dayLoad.containsKey(interviewerId)
        ? dayLoad.get(interviewerId)
        : 0;
      String candidateName = windowByInterviewer.get(interviewerId)
        .interviewerName;

      if (
        bestInterviewerId == null ||
        candidateTotalLoad < bestTotalLoad ||
        (candidateTotalLoad == bestTotalLoad &&
        candidateDayLoad < bestDayLoad) ||
        (candidateTotalLoad == bestTotalLoad &&
        candidateDayLoad == bestDayLoad &&
        compareText(candidateName, bestName) < 0)
      ) {
        bestInterviewerId = interviewerId;
        bestTotalLoad = candidateTotalLoad;
        bestDayLoad = candidateDayLoad;
        bestName = candidateName;
      }
    }

    return bestInterviewerId == null
      ? null
      : windowByInterviewer.get(bestInterviewerId);
  }

  private static Id createBookedAvailabilitySlot(
    Interview__c interviewRecord,
    CandidateAvailabilityWindow selectedWindow,
    Datetime selectedStart,
    Datetime selectedEnd
  ) {
    if (selectedWindow == null || selectedWindow.interviewerId == null) {
      throw new AuraHandledException(
        'This slot is no longer available. Please choose another slot.'
      );
    }

    List<Availability_Slot__c> existingBookings = [
      SELECT Id, Booked_Interview__c, Start_DateTime__c, End_DateTime__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :selectedWindow.interviewerId
        AND Is_Booked__c = TRUE
        AND Deactivated_Date__c = NULL
        AND Start_DateTime__c < :selectedEnd
        AND End_DateTime__c > :selectedStart
      WITH SYSTEM_MODE
      FOR UPDATE
    ];

    for (Availability_Slot__c existingBooking : existingBookings) {
      if (existingBooking.Booked_Interview__c == interviewRecord.Id) {
        return existingBooking.Id;
      }

      throw new AuraHandledException(
        'This slot is no longer available. Please choose another slot.'
      );
    }

    Availability_Slot__c bookedSlot = new Availability_Slot__c();
    bookedSlot.Interviewer__c = selectedWindow.interviewerId;
    bookedSlot.Interview_Stage__c = interviewRecord.Interview_Stage__c;
    bookedSlot.Is_Recurring__c = false;
    bookedSlot.Is_Blocked__c = false;
    bookedSlot.Is_Booked__c = true;
    bookedSlot.Booked_Interview__c = interviewRecord.Id;
    bookedSlot.Day_Of_Week__c = selectedStart.format('EEEE');
    bookedSlot.Start_DateTime__c = selectedStart;
    bookedSlot.End_DateTime__c = selectedEnd;

    insert as system bookedSlot;

    return bookedSlot.Id;
  }

  private static Map<Id, Integer> countInterviewerLoad(
    Set<Id> interviewerIds,
    Id stageId,
    Id jobPositionId,
    Date selectedDate
  ) {
    Map<Id, Integer> result = new Map<Id, Integer>();

    if (interviewerIds == null || interviewerIds.isEmpty()) {
      return result;
    }

    List<Interview__c> interviews = [
      SELECT Id, Interviewer__c, Scheduled_DateTime__c
      FROM Interview__c
      WHERE
        Interviewer__c IN :interviewerIds
        AND Interview_Stage__c = :stageId
        AND Job_Application__r.Job_Position__c = :jobPositionId
        AND Status__c IN :LOAD_STATUSES
      WITH SYSTEM_MODE
    ];

    for (Interview__c interviewRecord : interviews) {
      if (selectedDate != null) {
        if (
          interviewRecord.Scheduled_DateTime__c == null ||
          interviewRecord.Scheduled_DateTime__c.date() != selectedDate
        ) {
          continue;
        }
      }

      Integer current = result.containsKey(interviewRecord.Interviewer__c)
        ? result.get(interviewRecord.Interviewer__c)
        : 0;

      result.put(interviewRecord.Interviewer__c, current + 1);
    }

    return result;
  }

  private static void validateCandidateHasNoOverlappingInterview(
    Id candidateId,
    Id currentInterviewId,
    Datetime selectedStart,
    Datetime selectedEnd
  ) {
    if (
      candidateHasOverlap(
        candidateId,
        currentInterviewId,
        selectedStart,
        selectedEnd
      )
    ) {
      throw new AuraHandledException(
        'You already have another interview scheduled during this time.'
      );
    }
  }

  private static Boolean candidateHasOverlap(
    Id candidateId,
    Id currentInterviewId,
    Datetime selectedStart,
    Datetime selectedEnd
  ) {
    if (candidateId == null || selectedStart == null || selectedEnd == null) {
      return false;
    }

    List<Interview__c> scheduledInterviews = [
      SELECT Id, Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
      FROM Interview__c
      WHERE
        Id != :currentInterviewId
        AND Job_Application__r.Candidate__c = :candidateId
        AND Status__c = :STATUS_SCHEDULED
        AND Scheduled_DateTime__c != NULL
      WITH SYSTEM_MODE
    ];

    for (Interview__c existingInterview : scheduledInterviews) {
      Integer existingDuration = existingInterview.Interview_Stage__r.Duration_Minutes__c !=
        null
        ? Integer.valueOf(
            existingInterview.Interview_Stage__r.Duration_Minutes__c
          )
        : 60;

      Datetime existingStart = existingInterview.Scheduled_DateTime__c;
      Datetime existingEnd = existingStart.addMinutes(existingDuration);

      if (existingStart < selectedEnd && existingEnd > selectedStart) {
        return true;
      }
    }

    return false;
  }

  private static Integer getDurationMinutes(Interview__c interviewRecord) {
    if (
      interviewRecord.Interview_Stage__r != null &&
      interviewRecord.Interview_Stage__r.Duration_Minutes__c != null &&
      interviewRecord.Interview_Stage__r.Duration_Minutes__c > 0
    ) {
      return Integer.valueOf(
        interviewRecord.Interview_Stage__r.Duration_Minutes__c
      );
    }

    return 60;
  }

  private static Datetime parseClientDateTime(String value) {
    if (String.isBlank(value)) {
      throw new AuraHandledException('Selected slot is required.');
    }

    String normalized = value.trim();

    try {
      if (normalized.contains('T')) {
        return (Datetime) JSON.deserialize(
          '"' + normalized + '"',
          Datetime.class
        );
      }

      return Datetime.valueOf(normalized);
    } catch (Exception parseException) {
      throw new AuraHandledException(
        'Selected slot format is invalid: ' + normalized
      );
    }
  }

  private static String getMondayAsString(Date inputDate) {
    Date baseMonday = Date.newInstance(1900, 1, 1);
    Integer daysFromBase = baseMonday.daysBetween(inputDate);
    Integer offset = Math.mod(daysFromBase, 7);

    if (offset < 0) {
      offset += 7;
    }

    Date monday = inputDate.addDays(-offset);
    return String.valueOf(monday);
  }

  private static Integer minutesSinceMidnight(Time value) {
    if (value == null) {
      return 0;
    }

    return (value.hour() * 60) + value.minute();
  }

  private static String buildSlotKey(Datetime startDt, Datetime endDt) {
    return String.valueOf(startDt.getTime()) +
      '|' +
      String.valueOf(endDt.getTime());
  }

  private static Boolean sameInstant(Datetime leftValue, Datetime rightValue) {
    if (leftValue == null || rightValue == null) {
      return false;
    }

    return leftValue.getTime() == rightValue.getTime();
  }

  private static Integer compareText(String leftValue, String rightValue) {
    String leftText = leftValue == null ? '' : leftValue;
    String rightText = rightValue == null ? '' : rightValue;

    return leftText.compareTo(rightText);
  }

  private class PublicSlotComparator implements Comparator<AvailabilitySlotService.TimeSlotDTO> {
    public Integer compare(
      AvailabilitySlotService.TimeSlotDTO a,
      AvailabilitySlotService.TimeSlotDTO b
    ) {
      if (a.startDt == b.startDt) {
        return 0;
      }

      return a.startDt < b.startDt ? -1 : 1;
    }
  }
}
