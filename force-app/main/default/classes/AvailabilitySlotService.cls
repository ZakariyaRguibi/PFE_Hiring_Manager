/**
 * @description Computes available interview time slots from recurring and non-recurring availability windows.
 * Handles single-interviewer scheduling, multi-interviewer stage scheduling, and HR read-only views.
 */
public without sharing class AvailabilitySlotService {
  private static Map<String, List<TimeSlotDTO>> stageSlotCache = new Map<String, List<TimeSlotDTO>>();

  public class TimeSlotDTO {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public DateTime startDt;
    @AuraEnabled
    public DateTime endDt;
    @AuraEnabled
    public String interviewerId;
    @AuraEnabled
    public String interviewerName;
    @AuraEnabled
    public String availabilitySlotId;
  }

  @AuraEnabled
  public static List<TimeSlotDTO> getAvailableSlotsForInterview(
    Id interviewId,
    String weekStart
  ) {
    try {
      Interview__c interview = [
        SELECT
          Id,
          Interviewer__c,
          Interviewer__r.Name,
          Interview_Stage__r.Duration_Minutes__c,
          Status__c
        FROM Interview__c
        WHERE Id = :interviewId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      if (
        interview.Status__c == 'Cancelled' ||
        interview.Status__c == 'Completed'
      ) {
        throw new AuraHandledException(
          'This interview is ' +
            interview.Status__c +
            ' and cannot be scheduled.'
        );
      }

      if (interview.Interviewer__c == null) {
        throw new AuraHandledException(
          'No interviewer assigned to this interview.'
        );
      }

      Integer durationMin = parseDuration(
        interview.Interview_Stage__r.Duration_Minutes__c
      );
      Date startDate = parseWeekStart(weekStart);
      Date endDate = startDate.addDays(7);

      List<TimeSlotDTO> result = computeSlotsForInterviewer(
        interview.Interviewer__c,
        interview.Interviewer__r.Name,
        durationMin,
        startDate,
        endDate,
        interviewId
      );

      result.sort(new TimeSlotComparator());
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not compute available slots: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static List<TimeSlotDTO> getAvailableSlotsForStage(
    Id stageId,
    String weekStart
  ) {
    return getAvailableSlotsForStageInternal(stageId, weekStart, false);
  }

  public static List<TimeSlotDTO> getAvailableSlotsForStage(
    Id stageId,
    String weekStart,
    Boolean includePastSlots
  ) {
    return getAvailableSlotsForStageInternal(
      stageId,
      weekStart,
      includePastSlots == true
    );
  }

  private static List<TimeSlotDTO> getAvailableSlotsForStageInternal(
    Id stageId,
    String weekStart,
    Boolean includePastSlots
  ) {
    String cacheKey =
      String.valueOf(stageId) +
      '|' +
      String.valueOf(weekStart) +
      '|' +
      String.valueOf(includePastSlots == true);

    if (stageSlotCache.containsKey(cacheKey)) {
      return cloneSlots(stageSlotCache.get(cacheKey));
    }

    try {
      Interview_Stage__c stage = [
        SELECT Id, Duration_Minutes__c
        FROM Interview_Stage__c
        WHERE Id = :stageId
        WITH SYSTEM_MODE
        LIMIT 1
      ];

      Integer durationMin = parseDuration(stage.Duration_Minutes__c);

      List<Interview_Stage_Team_Member__c> members = [
        SELECT Interviewer__c, Interviewer__r.Name
        FROM Interview_Stage_Team_Member__c
        WHERE Interview_Stage__c = :stageId
        WITH SYSTEM_MODE
      ];

      if (members.isEmpty()) {
        stageSlotCache.put(cacheKey, new List<TimeSlotDTO>());
        return new List<TimeSlotDTO>();
      }

      Date startDate = parseWeekStart(weekStart);
      Date endDate = startDate.addDays(7);

      List<TimeSlotDTO> allSlots = new List<TimeSlotDTO>();

      for (Interview_Stage_Team_Member__c member : members) {
        if (member.Interviewer__c == null) {
          continue;
        }

        allSlots.addAll(
          computeSlotsForInterviewer(
            member.Interviewer__c,
            member.Interviewer__r != null ? member.Interviewer__r.Name : null,
            durationMin,
            startDate,
            endDate,
            null,
            includePastSlots
          )
        );
      }

      allSlots.sort(new TimeSlotComparator());
      stageSlotCache.put(cacheKey, cloneSlots(allSlots));

      return allSlots;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not compute stage availability: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Availability_Slot__c> getWindowsForJob(Id jobPositionId) {
    try {
      List<Interview_Stage_Team_Member__c> members = [
        SELECT Interviewer__c
        FROM Interview_Stage_Team_Member__c
        WHERE Interview_Stage__r.Job_Position__c = :jobPositionId
        WITH SYSTEM_MODE
      ];

      Set<Id> interviewerIds = new Set<Id>();

      for (Interview_Stage_Team_Member__c member : members) {
        if (member.Interviewer__c != null) {
          interviewerIds.add(member.Interviewer__c);
        }
      }

      if (interviewerIds.isEmpty()) {
        return new List<Availability_Slot__c>();
      }

      return [
        SELECT
          Id,
          Interviewer__c,
          Interviewer__r.Name,
          Day_Of_Week__c,
          Start_DateTime__c,
          End_DateTime__c,
          Is_Recurring__c,
          Is_Blocked__c,
          Is_Booked__c
        FROM Availability_Slot__c
        WHERE
          Interviewer__c IN :interviewerIds
          AND Is_Blocked__c = FALSE
          AND (Is_Booked__c = FALSE
          OR Is_Booked__c = NULL)
          AND Deactivated_Date__c = NULL
        WITH SYSTEM_MODE
        ORDER BY Interviewer__c, Day_Of_Week__c, Start_DateTime__c
      ];
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not load windows: ' + e.getMessage()
      );
    }
  }

  public static List<TimeSlotDTO> computeSlotsForInterviewer(
    Id interviewerId,
    String interviewerName,
    Integer durationMin,
    Date startDate,
    Date endDate,
    Id excludeInterviewId
  ) {
    return computeSlotsForInterviewer(
      interviewerId,
      interviewerName,
      durationMin,
      startDate,
      endDate,
      excludeInterviewId,
      false
    );
  }

  public static List<TimeSlotDTO> computeSlotsForInterviewer(
    Id interviewerId,
    String interviewerName,
    Integer durationMin,
    Date startDate,
    Date endDate,
    Id excludeInterviewId,
    Boolean includePastSlots
  ) {
    if (interviewerId == null || startDate == null || endDate == null) {
      return new List<TimeSlotDTO>();
    }

    if (durationMin == null || durationMin <= 0) {
      durationMin = 60;
    }

    DateTime rangeStart = DateTime.newInstance(
      startDate,
      Time.newInstance(0, 0, 0, 0)
    );
    DateTime rangeEnd = DateTime.newInstance(
      endDate,
      Time.newInstance(0, 0, 0, 0)
    );

    List<Availability_Slot__c> windows = [
      SELECT
        Id,
        Start_DateTime__c,
        End_DateTime__c,
        Day_Of_Week__c,
        Is_Recurring__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :interviewerId
        AND Is_Blocked__c = FALSE
        AND (Is_Booked__c = FALSE
        OR Is_Booked__c = NULL)
        AND Deactivated_Date__c = NULL
        AND (Is_Recurring__c = TRUE
        OR (Is_Recurring__c = FALSE
        AND Start_DateTime__c >= :rangeStart
        AND Start_DateTime__c < :rangeEnd))
      WITH SYSTEM_MODE
    ];

    if (windows.isEmpty()) {
      return new List<TimeSlotDTO>();
    }

    List<DateTime[]> busyIntervals = new List<DateTime[]>();

    for (Availability_Slot__c blockSlot : [
      SELECT Start_DateTime__c, End_DateTime__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :interviewerId
        AND Is_Recurring__c = FALSE
        AND Is_Blocked__c = TRUE
        AND Start_DateTime__c >= :rangeStart
        AND Start_DateTime__c < :rangeEnd
      WITH SYSTEM_MODE
    ]) {
      if (
        blockSlot.Start_DateTime__c != null &&
        blockSlot.End_DateTime__c != null
      ) {
        busyIntervals.add(
          new List<DateTime>{
            blockSlot.Start_DateTime__c,
            blockSlot.End_DateTime__c
          }
        );
      }
    }

    List<Availability_Slot__c> bookedSlots;

    if (excludeInterviewId == null) {
      bookedSlots = [
        SELECT Start_DateTime__c, End_DateTime__c
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :interviewerId
          AND Is_Booked__c = TRUE
          AND Start_DateTime__c >= :rangeStart
          AND Start_DateTime__c < :rangeEnd
        WITH SYSTEM_MODE
      ];
    } else {
      bookedSlots = [
        SELECT Start_DateTime__c, End_DateTime__c
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :interviewerId
          AND Is_Booked__c = TRUE
          AND Start_DateTime__c >= :rangeStart
          AND Start_DateTime__c < :rangeEnd
          AND Booked_Interview__c != :excludeInterviewId
        WITH SYSTEM_MODE
      ];
    }

    for (Availability_Slot__c bookedSlot : bookedSlots) {
      if (
        bookedSlot.Start_DateTime__c != null &&
        bookedSlot.End_DateTime__c != null
      ) {
        busyIntervals.add(
          new List<DateTime>{
            bookedSlot.Start_DateTime__c,
            bookedSlot.End_DateTime__c
          }
        );
      }
    }

    List<Interview__c> bookedInterviews;

    if (excludeInterviewId == null) {
      bookedInterviews = [
        SELECT Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
        FROM Interview__c
        WHERE
          Interviewer__c = :interviewerId
          AND Status__c != 'Cancelled'
          AND Scheduled_DateTime__c >= :rangeStart
          AND Scheduled_DateTime__c < :rangeEnd
        WITH SYSTEM_MODE
      ];
    } else {
      bookedInterviews = [
        SELECT Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
        FROM Interview__c
        WHERE
          Interviewer__c = :interviewerId
          AND Status__c != 'Cancelled'
          AND Scheduled_DateTime__c >= :rangeStart
          AND Scheduled_DateTime__c < :rangeEnd
          AND Id != :excludeInterviewId
        WITH SYSTEM_MODE
      ];
    }

    for (Interview__c bookedInterview : bookedInterviews) {
      if (bookedInterview.Scheduled_DateTime__c == null) {
        continue;
      }

      Integer bookedDuration = parseDuration(
        bookedInterview.Interview_Stage__r.Duration_Minutes__c
      );

      busyIntervals.add(
        new List<DateTime>{
          bookedInterview.Scheduled_DateTime__c,
          bookedInterview.Scheduled_DateTime__c.addMinutes(bookedDuration)
        }
      );
    }

    Map<String, Integer> dayOffset = new Map<String, Integer>{
      'Monday' => 0,
      'Tuesday' => 1,
      'Wednesday' => 2,
      'Thursday' => 3,
      'Friday' => 4,
      'Saturday' => 5,
      'Sunday' => 6
    };

    List<TimeSlotDTO> result = new List<TimeSlotDTO>();
    DateTime nowDt = DateTime.now();

    for (Availability_Slot__c window : windows) {
      DateTime windowStart;
      DateTime windowEnd;

      if (window.Is_Recurring__c == true) {
        Integer offset = dayOffset.get(window.Day_Of_Week__c);

        if (
          offset == null ||
          window.Start_DateTime__c == null ||
          window.End_DateTime__c == null
        ) {
          continue;
        }

        Date slotDate = startDate.addDays(offset);

        windowStart = DateTime.newInstance(
          slotDate,
          window.Start_DateTime__c.time()
        );
        windowEnd = DateTime.newInstance(
          slotDate,
          window.End_DateTime__c.time()
        );
      } else {
        windowStart = window.Start_DateTime__c;
        windowEnd = window.End_DateTime__c;
      }

      if (
        windowStart == null ||
        windowEnd == null ||
        windowStart >= windowEnd
      ) {
        continue;
      }

      DateTime cursor = windowStart;

      while (cursor.addMinutes(durationMin) <= windowEnd) {
        DateTime subEnd = cursor.addMinutes(durationMin);

        if (
          (includePastSlots == true || cursor >= nowDt) &&
          !overlapsAny(cursor, subEnd, busyIntervals)
        ) {
          TimeSlotDTO dto = new TimeSlotDTO();
          dto.startDt = cursor;
          dto.endDt = subEnd;
          dto.interviewerId = interviewerId;
          dto.interviewerName = interviewerName;
          dto.availabilitySlotId = window.Id;
          dto.label = formatSlotLabel(cursor, subEnd);
          result.add(dto);
        }

        cursor = cursor.addMinutes(durationMin);
      }
    }

    return result;
  }

  public static Date currentMonday() {
    Date today = Date.today();
    Datetime dt = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));
    String dayOfWeek = dt.format('EEEE');

    Map<String, Integer> backDays = new Map<String, Integer>{
      'Monday' => 0,
      'Tuesday' => 1,
      'Wednesday' => 2,
      'Thursday' => 3,
      'Friday' => 4,
      'Saturday' => 5,
      'Sunday' => 6
    };

    Integer back = backDays.containsKey(dayOfWeek)
      ? backDays.get(dayOfWeek)
      : 0;
    return today.addDays(-back);
  }

  public static String formatSlotLabel(DateTime slotStart, DateTime slotEnd) {
    return getDayName(slotStart) +
      ' ' +
      formatTime(slotStart) +
      ' – ' +
      formatTime(slotEnd);
  }

  private static Boolean overlapsAny(
    DateTime subStart,
    DateTime subEnd,
    List<DateTime[]> busyIntervals
  ) {
    for (DateTime[] interval : busyIntervals) {
      if (subStart < interval[1] && subEnd > interval[0]) {
        return true;
      }
    }

    return false;
  }

  private static String formatTime(DateTime dt) {
    return String.valueOf(dt.hour()).leftPad(2, '0') +
      ':' +
      String.valueOf(dt.minute()).leftPad(2, '0');
  }

  private static String getDayName(DateTime dt) {
    Date d = Date.newInstance(dt.year(), 1, 1).addDays(dt.dayOfYear() - 1);
    DateTime midnight = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
    return midnight.format('EEE');
  }

  private static Date parseWeekStart(String weekStart) {
    return String.isBlank(weekStart)
      ? currentMonday()
      : Date.valueOf(weekStart);
  }

  private static Integer parseDuration(Decimal durationMinutes) {
    return durationMinutes != null ? Integer.valueOf(durationMinutes) : 60;
  }

  private static List<TimeSlotDTO> cloneSlots(List<TimeSlotDTO> source) {
    List<TimeSlotDTO> result = new List<TimeSlotDTO>();

    if (source == null) {
      return result;
    }

    for (TimeSlotDTO sourceSlot : source) {
      TimeSlotDTO cloned = new TimeSlotDTO();
      cloned.label = sourceSlot.label;
      cloned.startDt = sourceSlot.startDt;
      cloned.endDt = sourceSlot.endDt;
      cloned.interviewerId = sourceSlot.interviewerId;
      cloned.interviewerName = sourceSlot.interviewerName;
      cloned.availabilitySlotId = sourceSlot.availabilitySlotId;
      result.add(cloned);
    }

    return result;
  }

  private class TimeSlotComparator implements Comparator<TimeSlotDTO> {
    public Integer compare(TimeSlotDTO a, TimeSlotDTO b) {
      if (a.startDt == b.startDt) {
        return 0;
      }

      return a.startDt < b.startDt ? -1 : 1;
    }
  }
}
