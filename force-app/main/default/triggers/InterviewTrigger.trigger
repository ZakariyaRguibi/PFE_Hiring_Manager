trigger InterviewTrigger on Interview__c (after insert, after update) {
    List<Interview__c> interviewsToNotify = new List<Interview__c>();
    List<Interview__c> withdrawnOrNoShow = new List<Interview__c>();

    for (Interview__c interview : Trigger.new) {
        Interview__c oldInterview = Trigger.isUpdate
            ? Trigger.oldMap.get(interview.Id)
            : null;

        // ── Interview invitation ──
        if (interview.Interview_Date__c != null &&
            (oldInterview == null || oldInterview.Interview_Date__c == null)) {
            interviewsToNotify.add(interview);
        }

        // ── Withdrawn or No Show ──
        if (Trigger.isUpdate && oldInterview != null) {
            Boolean newlyWithdrawn = interview.Candidate_Withdrawn__c == true
                && oldInterview.Candidate_Withdrawn__c != true;
            Boolean newlyNoShow = interview.No_Show__c == true
                && oldInterview.No_Show__c != true;

            if (newlyWithdrawn || newlyNoShow) {
                withdrawnOrNoShow.add(interview);
            }
        }
    }

    if (!interviewsToNotify.isEmpty()) {
        InterviewEmailService.sendInterviewInvitation(interviewsToNotify);
    }
    if (!withdrawnOrNoShow.isEmpty()) {
        InterviewEmailService.sendWithdrawnOrNoShowEmails(withdrawnOrNoShow);
    }
}