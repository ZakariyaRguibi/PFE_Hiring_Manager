public without sharing class InterviewerAvailabilityController {
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

  @AuraEnabled
  public static List<Availability_Slot__c> getMyWindows(String weekStart) {
    Date startDate = String.isBlank(weekStart)
      ? AvailabilitySlotService.currentMonday()
      : Date.valueOf(weekStart);
    Date endDate = startDate.addDays(7);
    DateTime weekStartDt = DateTime.newInstanceGmt(
      startDate,
      Time.newInstance(0, 0, 0, 0)
    );
    DateTime weekEndDt = DateTime.newInstanceGmt(
      endDate,
      Time.newInstance(0, 0, 0, 0)
    );
    return [
      SELECT
        Id,
        Name,
        Day_Of_Week__c,
        Start_DateTime__c,
        End_DateTime__c,
        Is_Recurring__c,
        Is_Blocked__c,
        Deactivated_Date__c
      FROM Availability_Slot__c
      WHERE
        Interviewer__c = :UserInfo.getUserId()
        AND ((Is_Recurring__c = TRUE
        AND (Deactivated_Date__c = NULL
        OR Deactivated_Date__c >= :endDate)
        AND (Effective_From__c = NULL
        OR Effective_From__c <= :startDate))
        OR (Is_Recurring__c = FALSE
        AND Is_Blocked__c = FALSE
        AND Deactivated_Date__c = NULL
        AND Start_DateTime__c >= :weekStartDt
        AND Start_DateTime__c < :weekEndDt))
      WITH USER_MODE
      ORDER BY Day_Of_Week__c, Start_DateTime__c
    ];
  }

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
      AvailabilitySlotService.clearCache();
      return slot.Is_Blocked__c;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not update window: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static void saveWindow(
    String dayOfWeek,
    String startTime,
    String endTime,
    String weekStart,
    Boolean isRecurring
  ) {
    try {
      if (String.isBlank(dayOfWeek))
        throw new AuraHandledException('Day of week is required.');
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
      Boolean recurring = (isRecurring == null || isRecurring);

      if (recurring) {
        Date baseDate = Date.newInstance(2000, 1, 3).addDays(offset);
        DateTime startDt = DateTime.newInstance(baseDate, startT);
        DateTime endDt = DateTime.newInstance(baseDate, endT);

        if (endDt <= startDt)
          throw new AuraHandledException('End time must be after start time.');

        Date effectiveFrom = String.isBlank(weekStart)
          ? AvailabilitySlotService.currentMonday()
          : Date.valueOf(weekStart);

        List<Availability_Slot__c> duplicates = [
          SELECT Id, Effective_From__c
          FROM Availability_Slot__c
          WHERE
            Interviewer__c = :UserInfo.getUserId()
            AND Is_Recurring__c = TRUE
            AND Deactivated_Date__c = NULL
            AND Day_Of_Week__c = :dayOfWeek
            AND Start_DateTime__c = :startDt
            AND End_DateTime__c = :endDt
          WITH USER_MODE
        ];
        if (!duplicates.isEmpty()) {
          Availability_Slot__c existing = duplicates[0];
          if (
            existing.Effective_From__c != null &&
            existing.Effective_From__c > effectiveFrom
          ) {
            existing.Effective_From__c = effectiveFrom;
            update as user existing;
            AvailabilitySlotService.clearCache();
            return;
          }
          throw new AuraHandledException(
            'You already have a window on ' + dayOfWeek + ' at this start time.'
          );
        }

        // Cross-type: recurring supersedes overlapping one-time slots — soft-delete them
        List<Availability_Slot__c> toDeactivate = new List<Availability_Slot__c>();
        for (Availability_Slot__c ot : [
          SELECT Id, Start_DateTime__c, End_DateTime__c
          FROM Availability_Slot__c
          WHERE
            Interviewer__c = :UserInfo.getUserId()
            AND Is_Recurring__c = FALSE
            AND Is_Blocked__c = FALSE
            AND Deactivated_Date__c = NULL
            AND Day_Of_Week__c = :dayOfWeek
          WITH USER_MODE
        ]) {
          Time otS = Time.newInstance(
            ot.Start_DateTime__c.hourGmt(),
            ot.Start_DateTime__c.minuteGmt(),
            0,
            0
          );
          Time otE = Time.newInstance(
            ot.End_DateTime__c.hourGmt(),
            ot.End_DateTime__c.minuteGmt(),
            0,
            0
          );
          if (startT < otE && endT > otS) {
            ot.Deactivated_Date__c = Date.today();
            toDeactivate.add(ot);
          }
        }
        if (!toDeactivate.isEmpty()) {
          update as user toDeactivate;
          AvailabilitySlotService.clearCache();
        }

        // Same-type: deactivate recurring slots fully encompassed by the new one
        List<Availability_Slot__c> encompassed = [
          SELECT Id
          FROM Availability_Slot__c
          WHERE
            Interviewer__c = :UserInfo.getUserId()
            AND Is_Recurring__c = TRUE
            AND Deactivated_Date__c = NULL
            AND Day_Of_Week__c = :dayOfWeek
            AND Start_DateTime__c >= :startDt
            AND End_DateTime__c <= :endDt
          WITH USER_MODE
        ];
        for (Availability_Slot__c ol : encompassed) {
          ol.Deactivated_Date__c = Date.today();
        }
        if (!encompassed.isEmpty()) {
          update as user encompassed;
          AvailabilitySlotService.clearCache();
        }

        // Check for remaining partial overlaps (old slot is bigger)
        List<Availability_Slot__c> remaining = [
          SELECT Start_DateTime__c, End_DateTime__c, Effective_From__c
          FROM Availability_Slot__c
          WHERE
            Interviewer__c = :UserInfo.getUserId()
            AND Is_Recurring__c = TRUE
            AND Deactivated_Date__c = NULL
            AND Day_Of_Week__c = :dayOfWeek
            AND Start_DateTime__c < :endDt
            AND End_DateTime__c > :startDt
          WITH USER_MODE
        ];
        if (!remaining.isEmpty()) {
          Availability_Slot__c c = remaining[0];
          String cS =
            String.valueOf(c.Start_DateTime__c.hourGmt()).leftPad(2, '0') +
            ':' +
            String.valueOf(c.Start_DateTime__c.minuteGmt()).leftPad(2, '0');
          String cE =
            String.valueOf(c.End_DateTime__c.hourGmt()).leftPad(2, '0') +
            ':' +
            String.valueOf(c.End_DateTime__c.minuteGmt()).leftPad(2, '0');
          String weekInfo = c.Effective_From__c != null
            ? ' (effective from week of ' +
              String.valueOf(c.Effective_From__c) +
              ')'
            : '';
          throw new AuraHandledException(
            'Overlaps with existing ' +
              dayOfWeek +
              ' ' +
              cS +
              ' – ' +
              cE +
              weekInfo +
              '. Create a window that fully covers it to replace it.'
          );
        }

        insert as user new Availability_Slot__c(
          Interviewer__c = UserInfo.getUserId(),
          Day_Of_Week__c = dayOfWeek,
          Start_DateTime__c = startDt,
          End_DateTime__c = endDt,
          Is_Recurring__c = true,
          Effective_From__c = effectiveFrom
        );
        AvailabilitySlotService.clearCache();
      } else {
        Date weekStartDate = String.isBlank(weekStart)
          ? AvailabilitySlotService.currentMonday()
          : Date.valueOf(weekStart);
        Date actualDate = weekStartDate.addDays(offset);
        DateTime startDt = DateTime.newInstanceGmt(actualDate, startT);
        DateTime endDt = DateTime.newInstanceGmt(actualDate, endT);

        if (endDt <= startDt)
          throw new AuraHandledException('End time must be after start time.');

        // Cross-type: block if a recurring slot overlaps on this day for this week
        Date weekEndDate = weekStartDate.addDays(7);
        for (Availability_Slot__c rec : [
          SELECT Start_DateTime__c, End_DateTime__c
          FROM Availability_Slot__c
          WHERE
            Interviewer__c = :UserInfo.getUserId()
            AND Is_Recurring__c = TRUE
            AND (Deactivated_Date__c = NULL
            OR Deactivated_Date__c >= :weekEndDate)
            AND (Effective_From__c = NULL
            OR Effective_From__c <= :weekStartDate)
            AND Day_Of_Week__c = :dayOfWeek
          WITH USER_MODE
        ]) {
          Time recS = Time.newInstance(
            rec.Start_DateTime__c.hourGmt(),
            rec.Start_DateTime__c.minuteGmt(),
            0,
            0
          );
          Time recE = Time.newInstance(
            rec.End_DateTime__c.hourGmt(),
            rec.End_DateTime__c.minuteGmt(),
            0,
            0
          );
          if (startT < recE && endT > recS) {
            throw new AuraHandledException(
              'A recurring window on ' +
                dayOfWeek +
                ' already covers this time.'
            );
          }
        }

        insert as user new Availability_Slot__c(
          Interviewer__c = UserInfo.getUserId(),
          Day_Of_Week__c = dayOfWeek,
          Start_DateTime__c = startDt,
          End_DateTime__c = endDt,
          Is_Recurring__c = false,
          Is_Blocked__c = false
        );
        AvailabilitySlotService.clearCache();
      }
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

  @AuraEnabled
  public static void deleteWindow(Id slotId) {
    try {
      Availability_Slot__c slot = [
        SELECT Id, Interviewer__c, Deactivated_Date__c
        FROM Availability_Slot__c
        WHERE Id = :slotId
        WITH USER_MODE
      ];
      if (slot.Interviewer__c != UserInfo.getUserId()) {
        throw new AuraHandledException('You can only delete your own windows.');
      }
      slot.Deactivated_Date__c = Date.today();
      update as user slot;
      AvailabilitySlotService.clearCache();
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not delete window: ' + e.getMessage()
      );
    }
  }

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
      DateTime blockStartDt = DateTime.newInstance(d, startT);
      DateTime blockEndDt = DateTime.newInstance(d, endT);

      List<Availability_Slot__c> existing = [
        SELECT Id
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Is_Recurring__c = FALSE
          AND Is_Blocked__c = TRUE
          AND Start_DateTime__c = :blockStartDt
          AND End_DateTime__c = :blockEndDt
        WITH USER_MODE
      ];
      if (!existing.isEmpty())
        return;

      insert as user new Availability_Slot__c(
        Interviewer__c = UserInfo.getUserId(),
        Day_Of_Week__c = window.Day_Of_Week__c,
        Start_DateTime__c = blockStartDt,
        End_DateTime__c = blockEndDt,
        Is_Recurring__c = false,
        Is_Blocked__c = true
      );
      AvailabilitySlotService.clearCache();
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not block window: ' + e.getMessage()
      );
    }
  }

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
      DateTime blockStartDt = DateTime.newInstance(d, startT);
      DateTime blockEndDt = DateTime.newInstance(d, endT);

      List<Availability_Slot__c> blocks = [
        SELECT Id
        FROM Availability_Slot__c
        WHERE
          Interviewer__c = :UserInfo.getUserId()
          AND Is_Recurring__c = FALSE
          AND Is_Blocked__c = TRUE
          AND Start_DateTime__c = :blockStartDt
          AND End_DateTime__c = :blockEndDt
        WITH USER_MODE
      ];
      if (!blocks.isEmpty()) {
        delete as user blocks;
        AvailabilitySlotService.clearCache();
      }
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not unblock window: ' + e.getMessage()
      );
    }
  }

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
