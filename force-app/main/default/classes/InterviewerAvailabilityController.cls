/**
 * @description LWC controller for interviewer self-service availability management.
 * Handles CRUD on recurring availability windows, date-specific blocking, and scheduled interview retrieval.
 */
public with sharing class InterviewerAvailabilityController {
  /**
   * @description DTO for scheduled interview data displayed in the availability planner.
   */
  public class ScheduledInterviewDTO {
    @AuraEnabled
    public String interviewId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String stageName;
    @AuraEnabled
    public String candidateName;
    @AuraEnabled
    public String dayOfWeek;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public DateTime startDt;
    @AuraEnabled
    public DateTime endDt;
    @AuraEnabled
    public Integer durationMinutes;
  }

  /**
   * @description Returns the current user's recurring availability windows.
   * @return list of Availability_Slot__c records for the running user
   */
  @AuraEnabled(cacheable=true)
  public static List<Availability_Slot__c> getMyWindows() {
    return [
      SELECT
        Id,
        Name,
        Day_Of_Week__c,
        Start_DateTime__c,
        End_DateTime__c,
        Is_Recurring__c,
        Is_Blocked__c
      FROM Availability_Slot__c
      WHERE Interviewer__c = :UserInfo.getUserId() AND Is_Recurring__c = TRUE
      WITH USER_MODE
      ORDER BY Day_Of_Week__c, Start_DateTime__c
    ];
  }

  /**
   * @description Toggles the Is_Blocked__c flag on an availability window owned by the current user.
   * @param slotId the Availability_Slot__c record Id
   * @return the new Is_Blocked__c value
   */
  @AuraEnabled
  public static Boolean toggleWindowBlock(Id slotId) {
    try {
      Availability_Slot__c slot = [
        SELECT Id, Interviewer__c, Is_Blocked__c
        FROM Availability_Slot__c
        WHERE Id = :slotId
        WITH USER_MODE
      ];
      if (slot.Interviewer__c != UserInfo.getUserId()) {
        throw new AuraHandledException('You can only modify your own windows.');
      }
      slot.Is_Blocked__c = !slot.Is_Blocked__c;
      update as user slot;
      return slot.Is_Blocked__c;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not update window: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Creates a new recurring availability window for the current user.
   * @param dayOfWeek day name (e.g. "Monday")
   * @param startTime start time in HH:mm format
   * @param endTime end time in HH:mm format
   */
  @AuraEnabled
  public static void saveWindow(
    String dayOfWeek,
    String startTime,
    String endTime
  ) {
    try {
      if (String.isBlank(dayOfWeek)) {
        throw new AuraHandledException('Day of week is required.');
      }
      if (String.isBlank(startTime) || String.isBlank(endTime)) {
        throw new AuraHandledException('Start time and end time are required.');
      }

      List<String> startParts = startTime.split(':');
      List<String> endParts = endTime.split(':');
      Time startT = Time.newInstance(
        Integer.valueOf(startParts[0]),
        Integer.valueOf(startParts[1]),
        0,
        0
      );
      Time endT = Time.newInstance(
        Integer.valueOf(endParts[0]),
        Integer.valueOf(endParts[1]),
        0,
        0
      );

      Map<String, Integer> dayOffset = new Map<String, Integer>{
        'Monday' => 0,
        'Tuesday' => 1,
        'Wednesday' => 2,
        'Thursday' => 3,
        'Friday' => 4,
        'Saturday' => 5,
        'Sunday' => 6
      };
      Integer offset = dayOffset.containsKey(dayOfWeek)
        ? dayOffset.get(dayOfWeek)
        : 0;
      Date baseDate = Date.newInstance(2000, 1, 3).addDays(offset);
      DateTime startDt = DateTime.newInstance(baseDate, startT);
      DateTime endDt = DateTime.newInstance(baseDate, endT);

      if (endDt <= startDt) {
        throw new AuraHandledException('End time must be after start time.');
      }

      List<Availability_Slot__c> duplicates = [
        SELECT Id
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Is_Recurring__c = TRUE
          AND Day_Of_Week__c = :dayOfWeek
          AND Start_DateTime__c = :startDt
        WITH USER_MODE
      ];
      if (!duplicates.isEmpty()) {
        throw new AuraHandledException(
          'You already have a window on ' + dayOfWeek + ' at this start time.'
        );
      }

      insert as user new Availability_Slot__c(
        Interviewer__c = UserInfo.getUserId(),
        Day_Of_Week__c = dayOfWeek,
        Start_DateTime__c = startDt,
        End_DateTime__c = endDt,
        Is_Recurring__c = true
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Could not save window: ' + e.getDmlMessage(0)
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not save window: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Deletes a recurring availability window owned by the current user.
   * @param slotId the Availability_Slot__c record Id to delete
   */
  @AuraEnabled
  public static void deleteWindow(Id slotId) {
    try {
      Availability_Slot__c slot = [
        SELECT Id, Interviewer__c
        FROM Availability_Slot__c
        WHERE Id = :slotId
        WITH USER_MODE
      ];
      if (slot.Interviewer__c != UserInfo.getUserId()) {
        throw new AuraHandledException('You can only delete your own windows.');
      }
      delete as user slot;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not delete window: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Creates a one-off block record for a specific date, preventing scheduling on that window.
   * Idempotent: does nothing if a block already exists.
   * @param windowId the recurring Availability_Slot__c to block
   * @param targetDate ISO date string for the date to block
   */
  @AuraEnabled
  public static void blockWindowForDate(Id windowId, String targetDate) {
    try {
      Availability_Slot__c window = [
        SELECT
          Id,
          Interviewer__c,
          Start_DateTime__c,
          End_DateTime__c,
          Day_Of_Week__c
        FROM Availability_Slot__c
        WHERE Id = :windowId
        WITH USER_MODE
      ];
      if (window.Interviewer__c != UserInfo.getUserId()) {
        throw new AuraHandledException('You can only block your own windows.');
      }

      Date d = Date.valueOf(targetDate);
      Time startT = window.Start_DateTime__c.time();
      Time endT = window.End_DateTime__c.time();

      List<Availability_Slot__c> existing = [
        SELECT Id
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Is_Recurring__c = FALSE
          AND Is_Blocked__c = TRUE
          AND Start_DateTime__c = :DateTime.newInstance(d, startT)
          AND End_DateTime__c = :DateTime.newInstance(d, endT)
        WITH USER_MODE
      ];
      if (!existing.isEmpty()) {
        return;
      }

      insert as user new Availability_Slot__c(
        Interviewer__c = UserInfo.getUserId(),
        Day_Of_Week__c = window.Day_Of_Week__c,
        Start_DateTime__c = DateTime.newInstance(d, startT),
        End_DateTime__c = DateTime.newInstance(d, endT),
        Is_Recurring__c = false,
        Is_Blocked__c = true
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not block window: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Removes the one-off block record for a specific date, re-enabling scheduling.
   * @param windowId the recurring Availability_Slot__c to unblock
   * @param targetDate ISO date string for the date to unblock
   */
  @AuraEnabled
  public static void unblockWindowForDate(Id windowId, String targetDate) {
    try {
      Availability_Slot__c window = [
        SELECT Id, Interviewer__c, Start_DateTime__c, End_DateTime__c
        FROM Availability_Slot__c
        WHERE Id = :windowId
        WITH USER_MODE
      ];
      if (window.Interviewer__c != UserInfo.getUserId()) {
        throw new AuraHandledException(
          'You can only unblock your own windows.'
        );
      }

      Date d = Date.valueOf(targetDate);
      Time startT = window.Start_DateTime__c.time();
      Time endT = window.End_DateTime__c.time();

      List<Availability_Slot__c> blocks = [
        SELECT Id
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Is_Recurring__c = FALSE
          AND Is_Blocked__c = TRUE
          AND Start_DateTime__c = :DateTime.newInstance(d, startT)
          AND End_DateTime__c = :DateTime.newInstance(d, endT)
        WITH USER_MODE
      ];
      if (!blocks.isEmpty()) {
        delete as user blocks;
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not unblock window: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Returns the current user's non-cancelled scheduled interviews for a given week.
   * @param weekStart ISO date string for the Monday of the target week (nullable, defaults to current week)
   * @return list of ScheduledInterviewDTO sorted by scheduled time
   */
  @AuraEnabled
  public static List<ScheduledInterviewDTO> getMyScheduledInterviews(
    String weekStart
  ) {
    try {
      Date startDate = String.isBlank(weekStart)
        ? AvailabilitySlotService.currentMonday()
        : Date.valueOf(weekStart);
      Date endDate = startDate.addDays(7);

      List<Interview__c> interviews = [
        SELECT
          Id,
          Status__c,
          Scheduled_DateTime__c,
          Interview_Stage__r.Name,
          Interview_Stage__r.Duration_Minutes__c,
          Job_Application__r.Candidate__r.FirstName__c,
          Job_Application__r.Candidate__r.LastName__c
        FROM Interview__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Status__c != 'Cancelled'
          AND Scheduled_DateTime__c >= :DateTime.newInstance(
            startDate,
            Time.newInstance(0, 0, 0, 0)
          )
          AND Scheduled_DateTime__c < :DateTime.newInstance(
            endDate,
            Time.newInstance(0, 0, 0, 0)
          )
        WITH USER_MODE
        ORDER BY Scheduled_DateTime__c
      ];

      List<ScheduledInterviewDTO> result = new List<ScheduledInterviewDTO>();
      for (Interview__c iv : interviews) {
        ScheduledInterviewDTO dto = new ScheduledInterviewDTO();
        dto.interviewId = iv.Id;
        dto.status = iv.Status__c;
        dto.stageName = iv.Interview_Stage__r.Name;
        dto.startDt = iv.Scheduled_DateTime__c;
        Integer dur = (iv.Interview_Stage__r.Duration_Minutes__c != null)
          ? Integer.valueOf(iv.Interview_Stage__r.Duration_Minutes__c)
          : 60;
        dto.endDt = iv.Scheduled_DateTime__c.addMinutes(dur);
        dto.durationMinutes = dur;
        dto.candidateName =
          (iv.Job_Application__r.Candidate__r.FirstName__c != null
            ? iv.Job_Application__r.Candidate__r.FirstName__c + ' '
            : '') +
          (iv.Job_Application__r.Candidate__r.LastName__c != null
            ? iv.Job_Application__r.Candidate__r.LastName__c
            : '');
        dto.dayOfWeek = dto.startDt.format('EEEE');
        dto.label = AvailabilitySlotService.formatSlotLabel(
          dto.startDt,
          dto.endDt
        );
        result.add(dto);
      }
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not load scheduled interviews: ' + e.getMessage()
      );
    }
  }
}
