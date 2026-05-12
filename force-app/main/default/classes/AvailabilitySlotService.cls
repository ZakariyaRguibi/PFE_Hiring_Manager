/**
 * @description Computes available interview time slots from recurring availability windows.
 * Handles single-interviewer scheduling, multi-interviewer load-balanced stage scheduling,
 * and HR read-only views. Runs without sharing to access all interviewer data.
 */
public without sharing class AvailabilitySlotService {
    /**
     * @description Represents a bookable time slot returned to the UI.
     */
    public class TimeSlotDTO {
        @AuraEnabled public String label;
        @AuraEnabled public DateTime startDt;
        @AuraEnabled public DateTime endDt;
        @AuraEnabled public String interviewerId;
        @AuraEnabled public String interviewerName;
    }

    /**
     * @description Returns available time slots for a specific interview's assigned interviewer.
     * @param interviewId the Interview__c record to schedule
     * @param weekStart ISO date string for the Monday of the target week (nullable, defaults to current week)
     * @return list of bookable TimeSlotDTO sorted by start time
     */
    @AuraEnabled
    public static List<TimeSlotDTO> getAvailableSlotsForInterview(Id interviewId, String weekStart) {
        try {
            Interview__c interview = [
                SELECT Id, Interviewer__c, Interviewer__r.Name,
                       Interview_Stage__r.Duration_Minutes__c, Status__c
                FROM Interview__c
                WHERE Id = :interviewId
                WITH SYSTEM_MODE
            ];

            if (interview.Status__c == 'Cancelled' || interview.Status__c == 'Completed') {
                throw new AuraHandledException('This interview is ' + interview.Status__c + ' and cannot be scheduled.');
            }
            if (interview.Interviewer__c == null) {
                throw new AuraHandledException('No interviewer assigned to this interview.');
            }

            Integer durationMin = parseDuration(interview.Interview_Stage__r.Duration_Minutes__c);
            Date startDate = parseWeekStart(weekStart);
            Date endDate = startDate.addDays(7);

            List<TimeSlotDTO> result = computeSlotsForInterviewer(
                interview.Interviewer__c, interview.Interviewer__r.Name,
                durationMin, startDate, endDate, interviewId
            );
            result.sort(new TimeSlotComparator());
            return result;

        } catch (AuraHandledException e) { throw e;
        } catch (Exception e) { throw new AuraHandledException('Could not compute available slots: ' + e.getMessage()); }
    }

    /**
     * @description Returns de-duplicated available slots across all interviewers assigned to a stage.
     * When multiple interviewers share a time slot, keeps the one with the fewest global interviews.
     * @param stageId the Interview_Stage__c to compute availability for
     * @param weekStart ISO date string for the Monday of the target week (nullable, defaults to current week)
     * @return list of bookable TimeSlotDTO sorted by start time, one per unique start time
     */
    @AuraEnabled
    public static List<TimeSlotDTO> getAvailableSlotsForStage(Id stageId, String weekStart) {
        try {
            Interview_Stage__c stage = [
                SELECT Id, Duration_Minutes__c
                FROM Interview_Stage__c WHERE Id = :stageId
                WITH SYSTEM_MODE
            ];
            Integer durationMin = parseDuration(stage.Duration_Minutes__c);

            List<Interview_Stage_Team_Member__c> members = [
                SELECT Interviewer__c, Interviewer__r.Name
                FROM Interview_Stage_Team_Member__c
                WHERE Interview_Stage__c = :stageId
                WITH SYSTEM_MODE
            ];
            if (members.isEmpty()) {
                return new List<TimeSlotDTO>();
            }

            Date startDate = parseWeekStart(weekStart);
            Date endDate = startDate.addDays(7);

            // Collect interviewer Ids
            Set<Id> interviewerIds = new Set<Id>();
            for (Interview_Stage_Team_Member__c m : members) {
                interviewerIds.add(m.Interviewer__c);
            }

            // Global interview load: count all non-cancelled interviews per interviewer
            Map<Id, Integer> loadMap = new Map<Id, Integer>();
            for (Id iId : interviewerIds) { loadMap.put(iId, 0); }
            for (AggregateResult ar : [
                SELECT Interviewer__c iid, COUNT(Id) cnt
                FROM Interview__c
                WHERE Interviewer__c IN :interviewerIds
                  AND Status__c != 'Cancelled'
                WITH SYSTEM_MODE
                GROUP BY Interviewer__c
            ]) {
                loadMap.put((Id) ar.get('iid'), (Integer) ar.get('cnt'));
            }

            // Compute raw slots for all interviewers
            List<TimeSlotDTO> allSlots = new List<TimeSlotDTO>();
            for (Interview_Stage_Team_Member__c member : members) {
                allSlots.addAll(computeSlotsForInterviewer(
                    member.Interviewer__c, member.Interviewer__r.Name,
                    durationMin, startDate, endDate, null
                ));
            }

            // De-duplicate: for each unique startDt, keep only the least-loaded interviewer
            Map<String, TimeSlotDTO> deduped = new Map<String, TimeSlotDTO>();
            Map<String, Integer> dedupedLoad = new Map<String, Integer>();
            for (TimeSlotDTO slot : allSlots) {
                String key = String.valueOf(slot.startDt);
                Integer slotLoad = loadMap.containsKey(Id.valueOf(slot.interviewerId))
                    ? loadMap.get(Id.valueOf(slot.interviewerId)) : 0;
                if (!deduped.containsKey(key) || slotLoad < dedupedLoad.get(key)) {
                    deduped.put(key, slot);
                    dedupedLoad.put(key, slotLoad);
                }
            }

            List<TimeSlotDTO> result = deduped.values();
            result.sort(new TimeSlotComparator());
            return result;

        } catch (AuraHandledException e) { throw e;
        } catch (Exception e) { throw new AuraHandledException('Could not compute stage availability: ' + e.getMessage()); }
    }

    /**
     * @description Returns recurring availability windows for all interviewers assigned to a job position.
     * @param jobPositionId the Job_Position__c to retrieve windows for
     * @return list of Availability_Slot__c records ordered by interviewer, day, and start time
     */
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
            for (Interview_Stage_Team_Member__c m : members) {
                interviewerIds.add(m.Interviewer__c);
            }
            if (interviewerIds.isEmpty()) {
                return new List<Availability_Slot__c>();
            }

            return [
                SELECT Id, Interviewer__c, Interviewer__r.Name,
                       Day_Of_Week__c, Start_DateTime__c, End_DateTime__c, Is_Blocked__c
                FROM Availability_Slot__c
                WHERE Interviewer__c IN :interviewerIds
                  AND Is_Recurring__c = true
                WITH SYSTEM_MODE
                ORDER BY Interviewer__c, Day_Of_Week__c, Start_DateTime__c
            ];
        } catch (AuraHandledException e) { throw e;
        } catch (Exception e) { throw new AuraHandledException('Could not load windows: ' + e.getMessage()); }
    }


    /**
     * @description Computes available sub-slots for a single interviewer within a date range.
     * Expands recurring windows, subtracts blocked periods and booked interviews, then slices into duration-sized slots.
     * @param interviewerId the interviewer User Id
     * @param interviewerName the interviewer display name
     * @param durationMin slot duration in minutes
     * @param startDate first day of the range (inclusive)
     * @param endDate last day of the range (exclusive)
     * @param excludeInterviewId interview Id to exclude from busy intervals (nullable)
     * @return list of available TimeSlotDTO for this interviewer
     */
    public static List<TimeSlotDTO> computeSlotsForInterviewer(
        Id interviewerId, String interviewerName, Integer durationMin,
        Date startDate, Date endDate, Id excludeInterviewId
    ) {
        List<Availability_Slot__c> windows = [
            SELECT Id, Start_DateTime__c, End_DateTime__c, Day_Of_Week__c
            FROM Availability_Slot__c
            WHERE Interviewer__c  = :interviewerId
              AND Is_Recurring__c = true
              AND Is_Blocked__c   = false
            WITH SYSTEM_MODE
        ];
        if (windows.isEmpty()) {
            return new List<TimeSlotDTO>();
        }

        List<Availability_Slot__c> blocks = [
            SELECT Start_DateTime__c, End_DateTime__c
            FROM Availability_Slot__c
            WHERE Interviewer__c   = :interviewerId
              AND Is_Recurring__c  = false
              AND Is_Blocked__c    = true
              AND Start_DateTime__c >= :DateTime.newInstance(startDate, Time.newInstance(0,0,0,0))
              AND Start_DateTime__c <  :DateTime.newInstance(endDate,   Time.newInstance(0,0,0,0))
            WITH SYSTEM_MODE
        ];

        List<Interview__c> bookedInterviews;
        if (excludeInterviewId != null) {
            bookedInterviews = [
                SELECT Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
                FROM Interview__c
                WHERE Interviewer__c       = :interviewerId
                  AND Status__c           != 'Cancelled'
                  AND Scheduled_DateTime__c >= :DateTime.newInstance(startDate, Time.newInstance(0,0,0,0))
                  AND Scheduled_DateTime__c <  :DateTime.newInstance(endDate,   Time.newInstance(0,0,0,0))
                  AND Id                  != :excludeInterviewId
                WITH SYSTEM_MODE
            ];
        } else {
            bookedInterviews = [
                SELECT Scheduled_DateTime__c, Interview_Stage__r.Duration_Minutes__c
                FROM Interview__c
                WHERE Interviewer__c       = :interviewerId
                  AND Status__c           != 'Cancelled'
                  AND Scheduled_DateTime__c >= :DateTime.newInstance(startDate, Time.newInstance(0,0,0,0))
                  AND Scheduled_DateTime__c <  :DateTime.newInstance(endDate,   Time.newInstance(0,0,0,0))
                WITH SYSTEM_MODE
            ];
        }

        List<DateTime[]> busyIntervals = new List<DateTime[]>();
        for (Availability_Slot__c b : blocks) {
            busyIntervals.add(new DateTime[]{ b.Start_DateTime__c, b.End_DateTime__c });
        }
        for (Interview__c bi : bookedInterviews) {
            if (bi.Scheduled_DateTime__c == null) {
                continue;
            }
            Integer bookedDur = parseDuration(bi.Interview_Stage__r.Duration_Minutes__c);
            busyIntervals.add(new DateTime[]{ bi.Scheduled_DateTime__c, bi.Scheduled_DateTime__c.addMinutes(bookedDur) });
        }

        Map<String, Integer> dayOffset = new Map<String, Integer>{
            'Monday' => 0, 'Tuesday' => 1, 'Wednesday' => 2,
            'Thursday' => 3, 'Friday' => 4, 'Saturday' => 5, 'Sunday' => 6
        };
        List<TimeSlotDTO> result = new List<TimeSlotDTO>();

        for (Availability_Slot__c win : windows) {
            Integer offset = dayOffset.get(win.Day_Of_Week__c);
            if (offset == null) {
                continue;
            }

            Date slotDate = startDate.addDays(offset);
            DateTime winStart = DateTime.newInstance(slotDate, win.Start_DateTime__c.time());
            DateTime winEnd   = DateTime.newInstance(slotDate, win.End_DateTime__c.time());

            DateTime cursor = winStart;
            while (cursor.addMinutes(durationMin) <= winEnd) {
                DateTime subEnd = cursor.addMinutes(durationMin);
                if (!overlapsAny(cursor, subEnd, busyIntervals)) {
                    TimeSlotDTO dto = new TimeSlotDTO();
                    dto.startDt         = cursor;
                    dto.endDt           = subEnd;
                    dto.interviewerId   = interviewerId;
                    dto.interviewerName = interviewerName;
                    dto.label           = formatSlotLabel(cursor, subEnd);
                    result.add(dto);
                }
                cursor = cursor.addMinutes(durationMin);
            }
        }
        return result;
    }

    /**
     * @description Returns the Monday of the current week.
     * @return the Date of the current week's Monday
     */
    public static Date currentMonday() {
        Date today = Date.today();
        Datetime dt = DateTime.newInstance(today, Time.newInstance(0,0,0,0));
        String dayOfWeek = dt.format('EEEE');
        Map<String, Integer> backDays = new Map<String, Integer>{
            'Monday' => 0, 'Tuesday' => 1, 'Wednesday' => 2, 'Thursday' => 3,
            'Friday' => 4, 'Saturday' => 5, 'Sunday' => 6
        };
        Integer back = backDays.containsKey(dayOfWeek) ? backDays.get(dayOfWeek) : 0;
        return today.addDays(-back);
    }

    /**
     * @description Formats a human-readable slot label (e.g. "Mon 09:00 – 10:00").
     * @param slotStart slot start DateTime
     * @param slotEnd slot end DateTime
     * @return formatted label string
     */
    public static String formatSlotLabel(DateTime slotStart, DateTime slotEnd) {
        return getDayName(slotStart) + ' ' + formatTime(slotStart) + ' – ' + formatTime(slotEnd);
    }

    private static Boolean overlapsAny(DateTime subStart, DateTime subEnd, List<DateTime[]> busyIntervals) {
        for (DateTime[] interval : busyIntervals) {
            if (subStart < interval[1] && subEnd > interval[0]) {
                return true;
            }
        }
        return false;
    }

    private static String formatTime(DateTime dt) {
        return String.valueOf(dt.hour()).leftPad(2, '0') + ':' + String.valueOf(dt.minute()).leftPad(2, '0');
    }

    private static String getDayName(DateTime dt) {
        Date d = Date.newInstance(dt.year(), 1, 1).addDays(dt.dayOfYear() - 1);
        DateTime midnight = DateTime.newInstance(d, Time.newInstance(0,0,0,0));
        return midnight.format('EEE');
    }

    private static Date parseWeekStart(String weekStart) {
        return String.isBlank(weekStart) ? currentMonday() : Date.valueOf(weekStart);
    }

    private static Integer parseDuration(Decimal durationMinutes) {
        return (durationMinutes != null) ? Integer.valueOf(durationMinutes) : 60;
    }

    /**
     * @description Sorts TimeSlotDTO by startDt ascending.
     */
    private class TimeSlotComparator implements Comparator<TimeSlotDTO> {
        /**
         * @description Compares two TimeSlotDTO by startDt.
         * @param a first slot
         * @param b second slot
         * @return -1, 0, or 1
         */
        public Integer compare(TimeSlotDTO a, TimeSlotDTO b) {
            if (a.startDt == b.startDt) {
                return 0;
            }
            return a.startDt < b.startDt ? -1 : 1;
        }
    }
}
