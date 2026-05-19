public with sharing class InterviewPipelineController {

    // ── Data Transfer Objects ─────────────────────────────────────────────────

    public class StageWrapper {
        @AuraEnabled public Interview_Stage__c stage;
        @AuraEnabled public List<Interview_Stage_Team_Member__c> members;
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<StageWrapper> getStages(Id jobPositionId) {
        List<Interview_Stage__c> stages = [
            SELECT Id, Name, Stage_Number__c,
                   Start_Date__c, End_Date__c,
                   Max_Score__c, Passing_Threshold__c, Stage_Weight__c,
                   Duration_Minutes__c
            FROM Interview_Stage__c
            WHERE Job_Position__c = :jobPositionId
            ORDER BY Stage_Number__c ASC
        ];

        Set<Id> stageIds = new Map<Id, Interview_Stage__c>(stages).keySet();
        List<Interview_Stage_Team_Member__c> allMembers = [
            SELECT Id, Role__c, Interview_Stage__c,
                   Interviewer__c, Interviewer__r.Name
            FROM Interview_Stage_Team_Member__c
            WHERE Interview_Stage__c IN :stageIds
            ORDER BY CreatedDate ASC
        ];

        Map<Id, List<Interview_Stage_Team_Member__c>> membersByStage = new Map<Id, List<Interview_Stage_Team_Member__c>>();
        for (Interview_Stage_Team_Member__c m : allMembers) {
            if (!membersByStage.containsKey(m.Interview_Stage__c)) {
                membersByStage.put(m.Interview_Stage__c, new List<Interview_Stage_Team_Member__c>());
            }
            membersByStage.get(m.Interview_Stage__c).add(m);
        }

        List<StageWrapper> wrappers = new List<StageWrapper>();
        for (Interview_Stage__c s : stages) {
            StageWrapper w = new StageWrapper();
            w.stage = s;
            w.members = membersByStage.containsKey(s.Id) ? membersByStage.get(s.Id) : new List<Interview_Stage_Team_Member__c>();
            wrappers.add(w);
        }
        return wrappers;
    }

    // ── Stage mutations ───────────────────────────────────────────────────────

    @AuraEnabled
    public static Interview_Stage__c saveStage(Interview_Stage__c stage, Id jobPositionId) {
        if (stage.Id == null) {
            stage.Job_Position__c = jobPositionId;
            // Auto-assign next stage number if not set
            if (stage.Stage_Number__c == null) {
                AggregateResult[] agg = [
                    SELECT MAX(Stage_Number__c) maxNum
                    FROM Interview_Stage__c
                    WHERE Job_Position__c = :jobPositionId
                ];
                Decimal maxNum = (Decimal) agg[0].get('maxNum');
                stage.Stage_Number__c = maxNum != null ? maxNum + 1 : 1;
            }
            insert stage;
        } else {
            update stage;
        }
        return stage;
    }

    @AuraEnabled
    public static void deleteStage(Id stageId) {
        delete new Interview_Stage__c(Id = stageId);
    }

    @AuraEnabled
    public static void reorderStages(List<Id> orderedIds) {
        List<Interview_Stage__c> toUpdate = new List<Interview_Stage__c>();
        for (Integer i = 0; i < orderedIds.size(); i++) {
            toUpdate.add(new Interview_Stage__c(Id = orderedIds[i], Stage_Number__c = i + 1));
        }
        update toUpdate;
    }

    // ── Team member mutations ─────────────────────────────────────────────────

    @AuraEnabled
    public static Interview_Stage_Team_Member__c saveMember(Interview_Stage_Team_Member__c member) {
        if (member.Id == null) {
            insert member;
        } else {
            update member;
        }
        return member;
    }

    @AuraEnabled
    public static void deleteMember(Id memberId) {
        delete new Interview_Stage_Team_Member__c(Id = memberId);
    }
}