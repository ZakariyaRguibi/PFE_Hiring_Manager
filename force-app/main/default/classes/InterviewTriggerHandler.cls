public with sharing class InterviewTriggerHandler {

    public static void handle(List<Interview__c> newList, Map<Id, Interview__c> oldMap) {
        validateScoreAgainstMaxScore(newList);
        validateNoDuplicateDateTime(newList, oldMap);
    }

    /**
     * Score__c must be <= parent Interview_Stage__c.Max_Score__c
     */
    private static void validateScoreAgainstMaxScore(List<Interview__c> newList) {
        Set<Id> stageIds = new Set<Id>();
        for (Interview__c interview : newList) {
            if (interview.Interview_Stage__c != null && interview.Score__c != null) {
                stageIds.add(interview.Interview_Stage__c);
            }
        }
        if (stageIds.isEmpty()) return;

        Map<Id, Interview_Stage__c> stagesMap = new Map<Id, Interview_Stage__c>(
            [SELECT Id, Max_Score__c FROM Interview_Stage__c WHERE Id IN :stageIds]
        );

        for (Interview__c interview : newList) {
            if (interview.Interview_Stage__c != null && interview.Score__c != null) {
                Interview_Stage__c stage = stagesMap.get(interview.Interview_Stage__c);
                if (stage != null && stage.Max_Score__c != null && interview.Score__c > stage.Max_Score__c) {
                    interview.Score__c.addError(
                        'Score (' + interview.Score__c + ') cannot exceed the stage\'s Max Score (' + stage.Max_Score__c + ').'
                    );
                }
            }
        }
    }

    /**
     * A candidate (via Job_Application__c) cannot have two interviews at the same Scheduled_DateTime__c.
     */
    private static void validateNoDuplicateDateTime(List<Interview__c> newList, Map<Id, Interview__c> oldMap) {
        List<Interview__c> toCheck = new List<Interview__c>();
        for (Interview__c interview : newList) {
            if (interview.Job_Application__c == null || interview.Scheduled_DateTime__c == null) continue;
            // Skip if nothing relevant changed on update
            if (oldMap != null) {
                Interview__c old = oldMap.get(interview.Id);
                if (old.Scheduled_DateTime__c == interview.Scheduled_DateTime__c
                    && old.Job_Application__c == interview.Job_Application__c) {
                    continue;
                }
            }
            toCheck.add(interview);
        }
        if (toCheck.isEmpty()) return;

        Set<Id> appIds = new Set<Id>();
        Set<Datetime> dateTimes = new Set<Datetime>();
        for (Interview__c interview : toCheck) {
            appIds.add(interview.Job_Application__c);
            dateTimes.add(interview.Scheduled_DateTime__c);
        }

        List<Interview__c> existing = [
            SELECT Id, Job_Application__c, Scheduled_DateTime__c
            FROM Interview__c
            WHERE Job_Application__c IN :appIds
              AND Scheduled_DateTime__c IN :dateTimes
              AND Status__c NOT IN ('Cancelled', 'No Show')
        ];

        Map<String, Id> existingKeyToId = new Map<String, Id>();
        for (Interview__c ex : existing) {
            existingKeyToId.put(ex.Job_Application__c + '_' + ex.Scheduled_DateTime__c, ex.Id);
        }

        for (Interview__c interview : toCheck) {
            String key = interview.Job_Application__c + '_' + interview.Scheduled_DateTime__c;
            if (existingKeyToId.containsKey(key)) {
                Id conflictId = existingKeyToId.get(key);
                // Allow update of same record
                if (conflictId != interview.Id) {
                    interview.Scheduled_DateTime__c.addError(
                        'This candidate already has an interview scheduled at this date and time.'
                    );
                }
            }
        }
    }
}