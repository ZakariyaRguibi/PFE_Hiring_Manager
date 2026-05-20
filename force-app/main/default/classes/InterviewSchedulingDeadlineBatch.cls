/**
 * @description Expires pending self-scheduling interviews whose scheduling deadline has passed.
 * The candidate is withdrawn only when the system had valid slots available inside the allowed
 * scheduling window and the candidate still did not schedule.
 */
public without sharing class InterviewSchedulingDeadlineBatch implements Database.Batchable<SObject>, Schedulable {
  private static final String STATUS_PENDING = 'Pending_Scheduling';
  private static final String STATUS_CANCELLED = 'Cancelled';
  private static final String APP_STAGE_WITHDRAWN = 'Withdrawn';
  private static final String ISSUE_NO_AVAILABLE_SLOTS = 'No_Available_Slots';
  private static final String ISSUE_SLOT_BECAME_UNAVAILABLE = 'Slot_Became_Unavailable';

  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime nowDt = System.now();
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          CreatedDate,
          Status__c,
          Scheduled_DateTime__c,
          Scheduling_Deadline__c,
          Candidate_Tried_To_Schedule__c,
          Scheduling_Issue_Reason__c,
          Interview_Stage__c,
          Job_Application__c,
          Job_Application__r.Stage__c
        FROM Interview__c
        WHERE
          Status__c = :STATUS_PENDING
          AND Scheduled_DateTime__c = NULL
          AND Scheduling_Deadline__c != NULL
          AND Scheduling_Deadline__c < :nowDt
        WITH SYSTEM_MODE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<Interview__c> scope
  ) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    List<Interview__c> interviewsToCancel = new List<Interview__c>();
    Map<Id, Job_Application__c> applicationsToWithdraw = new Map<Id, Job_Application__c>();

    for (Interview__c interviewRecord : scope) {
      if (!shouldWithdrawForExpiredDeadline(interviewRecord)) {
        continue;
      }

      interviewsToCancel.add(
        new Interview__c(Id = interviewRecord.Id, Status__c = STATUS_CANCELLED)
      );

      if (interviewRecord.Job_Application__c != null) {
        applicationsToWithdraw.put(
          interviewRecord.Job_Application__c,
          new Job_Application__c(
            Id = interviewRecord.Job_Application__c,
            Stage__c = APP_STAGE_WITHDRAWN
          )
        );
      }
    }

    if (!interviewsToCancel.isEmpty()) {
      update as system interviewsToCancel;
    }
    if (!applicationsToWithdraw.isEmpty()) {
      update as system applicationsToWithdraw.values();
    }
  }

  public void finish(Database.BatchableContext context) {
    // No post-processing required.
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(new InterviewSchedulingDeadlineBatch(), 200);
  }

  private static Boolean shouldWithdrawForExpiredDeadline(
    Interview__c interviewRecord
  ) {
    if (
      interviewRecord == null ||
      interviewRecord.Interview_Stage__c == null ||
      interviewRecord.Scheduling_Deadline__c == null
    ) {
      return false;
    }

    Datetime earliestAllowedSlotStart = interviewRecord.CreatedDate.addDays(
      JobApplicationInterviewSchedulingService.MINIMUM_INTERVIEW_OFFSET_DAYS
    );

    if (interviewRecord.Candidate_Tried_To_Schedule__c == true) {
      return false;
    }

    // Normal flow: a pending interview is created only after valid availability exists.
    // This guard still protects candidates from manual/legacy pending interviews that
    // were never backed by any valid candidate-facing slot.
    return JobApplicationInterviewSchedulingService.hasValidCandidateSlot(
      interviewRecord.Interview_Stage__c,
      earliestAllowedSlotStart,
      interviewRecord.Scheduling_Deadline__c,
      true
    );
  }
}
