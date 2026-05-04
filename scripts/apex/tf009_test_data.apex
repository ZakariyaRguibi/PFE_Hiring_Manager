// =====================================================
// TF-009 TEST DATA SETUP - FIXED VERSION
// Creates real records to test the Job Position lifecycle flow manually.
//
// Run with:
// sf apex run --file scripts/apex/tf009_test_data.apex --target-org YOUR_ALIAS
// =====================================================

System.debug('========== TF-009 TEST DATA SETUP START ==========');

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

Schema.SObjectType jobPositionType = gd.get('Job_Position__c');
Schema.SObjectType interviewStageType = gd.get('Interview_Stage__c');

if (jobPositionType == null) {
    System.debug('ERROR: Job_Position__c does not exist.');
    System.assert(false, 'Job_Position__c does not exist.');
}

if (interviewStageType == null) {
    System.debug('ERROR: Interview_Stage__c does not exist.');
    System.assert(false, 'Interview_Stage__c does not exist.');
}

Map<String, Schema.SObjectField> jobFields =
    jobPositionType.getDescribe().fields.getMap();

Map<String, Schema.SObjectField> stageFields =
    interviewStageType.getDescribe().fields.getMap();

Boolean canOmitTitle =
    jobFields.containsKey('Title__c') &&
    jobFields.get('Title__c').getDescribe().isCreateable() &&
    jobFields.get('Title__c').getDescribe().isNillable();

Boolean canOmitPortalDescription =
    jobFields.containsKey('Portal_Description__c') &&
    jobFields.get('Portal_Description__c').getDescribe().isCreateable() &&
    jobFields.get('Portal_Description__c').getDescribe().isNillable();

Boolean canOmitApplicationDeadline =
    jobFields.containsKey('Application_Deadline__c') &&
    jobFields.get('Application_Deadline__c').getDescribe().isCreateable() &&
    jobFields.get('Application_Deadline__c').getDescribe().isNillable();

Boolean canOmitStageWeight =
    stageFields.containsKey('Stage_Weight__c') &&
    stageFields.get('Stage_Weight__c').getDescribe().isCreateable() &&
    stageFields.get('Stage_Weight__c').getDescribe().isNillable();

List<SObject> positionsToInsert = new List<SObject>();

List<Map<String, Object>> positionSpecs = new List<Map<String, Object>>{
    new Map<String, Object>{
        'key' => 'A1_DRAFT_VALID',
        'title' => 'TF009 A1 Draft Valid',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B1_MISSING_TITLE',
        'title' => null,
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B2_MISSING_PORTAL',
        'title' => 'TF009 B2 Missing Portal',
        'status' => 'Draft',
        'portal' => null,
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B3_MISSING_DEADLINE',
        'title' => 'TF009 B3 Missing Deadline',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => null
    },
    new Map<String, Object>{
        'key' => 'B4_EXPIRED_DEADLINE',
        'title' => 'TF009 B4 Expired Deadline',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => -1
    },
    new Map<String, Object>{
        'key' => 'B5_NO_STAGES',
        'title' => 'TF009 B5 No Stages',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B6_WEIGHTS_80',
        'title' => 'TF009 B6 Weights 80',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B7_WEIGHTS_120',
        'title' => 'TF009 B7 Weights 120',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'B8_BLANK_WEIGHT',
        'title' => 'TF009 B8 Blank Stage Weight',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'C1_VALID_PUBLISH',
        'title' => 'TF009 C1 Valid Publish',
        'status' => 'Draft',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'D1_OPEN_CLOSE',
        'title' => 'TF009 D1 Open Close',
        'status' => 'Open',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'E1_OPEN_CANCEL',
        'title' => 'TF009 E1 Open Cancel',
        'status' => 'Open',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'F1_CLOSED_VALID_DEADLINE',
        'title' => 'TF009 F1 Closed Valid Deadline',
        'status' => 'Closed',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    },
    new Map<String, Object>{
        'key' => 'F3_CLOSED_EXPIRED_DEADLINE',
        'title' => 'TF009 F3 Closed Expired Deadline',
        'status' => 'Closed',
        'portal' => 'Valid portal description',
        'deadlineOffset' => -1
    },
    new Map<String, Object>{
        'key' => 'G1_CANCELLED_FINAL',
        'title' => 'TF009 G1 Cancelled Final',
        'status' => 'Cancelled',
        'portal' => 'Valid portal description',
        'deadlineOffset' => 10
    }
};

for (Map<String, Object> spec : positionSpecs) {
    SObject jp = jobPositionType.newSObject();

    String key = (String) spec.get('key');
    String title = (String) spec.get('title');
    String status = (String) spec.get('status');
    String portal = (String) spec.get('portal');
    Object deadlineOffset = spec.get('deadlineOffset');

    if (
        jobFields.containsKey('Name') &&
        jobFields.get('Name').getDescribe().isCreateable()
    ) {
        jp.put('Name', key);
    }

    if (
        jobFields.containsKey('Title__c') &&
        jobFields.get('Title__c').getDescribe().isCreateable()
    ) {
        if (title != null) {
            jp.put('Title__c', title);
        } else if (!canOmitTitle) {
            jp.put('Title__c', 'TF009 B1 Title Required By Metadata');
            System.debug('WARNING: Title__c is required by metadata, so B1 cannot be created with a blank title.');
        }
    }

    if (
        jobFields.containsKey('Status__c') &&
        jobFields.get('Status__c').getDescribe().isCreateable()
    ) {
        jp.put('Status__c', status);
    }

    if (
        jobFields.containsKey('Portal_Description__c') &&
        jobFields.get('Portal_Description__c').getDescribe().isCreateable()
    ) {
        if (portal != null) {
            jp.put('Portal_Description__c', portal);
        } else if (!canOmitPortalDescription) {
            jp.put('Portal_Description__c', 'Portal description required by metadata');
            System.debug('WARNING: Portal_Description__c is required by metadata, so B2 cannot be created blank.');
        }
    }

    if (
        jobFields.containsKey('Application_Deadline__c') &&
        jobFields.get('Application_Deadline__c').getDescribe().isCreateable()
    ) {
        if (deadlineOffset != null) {
            jp.put('Application_Deadline__c', Date.today().addDays((Integer) deadlineOffset));
        } else if (!canOmitApplicationDeadline) {
            jp.put('Application_Deadline__c', Date.today().addDays(10));
            System.debug('WARNING: Application_Deadline__c is required by metadata, so B3 cannot be created blank.');
        }
    }

    if (
        jobFields.containsKey('Department__c') &&
        jobFields.get('Department__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            jobFields.get('Department__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            jp.put('Department__c', vals[0].getValue());
        }
    }

    if (
        jobFields.containsKey('Desired_Hires__c') &&
        jobFields.get('Desired_Hires__c').getDescribe().isCreateable()
    ) {
        jp.put('Desired_Hires__c', 1);
    }

    if (
        jobFields.containsKey('Open_Positions__c') &&
        jobFields.get('Open_Positions__c').getDescribe().isCreateable()
    ) {
        jp.put('Open_Positions__c', 1);
    }

    if (
        jobFields.containsKey('Filled_Positions__c') &&
        jobFields.get('Filled_Positions__c').getDescribe().isCreateable()
    ) {
        jp.put('Filled_Positions__c', 0);
    }

    positionsToInsert.add(jp);
}

insert positionsToInsert;

Map<String, Id> positionIdsByKey = new Map<String, Id>();

for (Integer i = 0; i < positionsToInsert.size(); i++) {
    positionIdsByKey.put(
        (String) positionSpecs[i].get('key'),
        (Id) positionsToInsert[i].get('Id')
    );
}

System.debug('Created Job Positions: ' + positionIdsByKey);

List<SObject> stagesToInsert = new List<SObject>();

List<Map<String, Object>> stageSpecs = new List<Map<String, Object>>{
    new Map<String, Object>{ 'positionKey' => 'A1_DRAFT_VALID', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'A1_DRAFT_VALID', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'A1_DRAFT_VALID', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B1_MISSING_TITLE', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B1_MISSING_TITLE', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B1_MISSING_TITLE', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B2_MISSING_PORTAL', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B2_MISSING_PORTAL', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B2_MISSING_PORTAL', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B3_MISSING_DEADLINE', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B3_MISSING_DEADLINE', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B3_MISSING_DEADLINE', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B4_EXPIRED_DEADLINE', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B4_EXPIRED_DEADLINE', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B4_EXPIRED_DEADLINE', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B6_WEIGHTS_80', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B6_WEIGHTS_80', 'weight' => 30, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B6_WEIGHTS_80', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B7_WEIGHTS_120', 'weight' => 50, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B7_WEIGHTS_120', 'weight' => 40, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B7_WEIGHTS_120', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'B8_BLANK_WEIGHT', 'weight' => 50, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'B8_BLANK_WEIGHT', 'weight' => null, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'B8_BLANK_WEIGHT', 'weight' => 50, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'C1_VALID_PUBLISH', 'weight' => 20, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'C1_VALID_PUBLISH', 'weight' => 50, 'order' => 2 },
    new Map<String, Object>{ 'positionKey' => 'C1_VALID_PUBLISH', 'weight' => 30, 'order' => 3 },

    new Map<String, Object>{ 'positionKey' => 'D1_OPEN_CLOSE', 'weight' => 100, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'E1_OPEN_CANCEL', 'weight' => 100, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'F1_CLOSED_VALID_DEADLINE', 'weight' => 100, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'F3_CLOSED_EXPIRED_DEADLINE', 'weight' => 100, 'order' => 1 },
    new Map<String, Object>{ 'positionKey' => 'G1_CANCELLED_FINAL', 'weight' => 100, 'order' => 1 }
};

for (Map<String, Object> spec : stageSpecs) {
    SObject st = interviewStageType.newSObject();

    String positionKey = (String) spec.get('positionKey');
    Integer orderNumber = (Integer) spec.get('order');
    Object weight = spec.get('weight');

    if (
        stageFields.containsKey('Name') &&
        stageFields.get('Name').getDescribe().isCreateable()
    ) {
        st.put('Name', 'TF009 Stage ' + orderNumber + ' - ' + positionKey);
    }

    if (
        stageFields.containsKey('Job_Position__c') &&
        stageFields.get('Job_Position__c').getDescribe().isCreateable()
    ) {
        st.put('Job_Position__c', positionIdsByKey.get(positionKey));
    }

    if (
        stageFields.containsKey('Stage_Weight__c') &&
        stageFields.get('Stage_Weight__c').getDescribe().isCreateable()
    ) {
        if (weight != null) {
            st.put('Stage_Weight__c', Decimal.valueOf(String.valueOf(weight)));
        } else if (!canOmitStageWeight) {
            st.put('Stage_Weight__c', 0);
            System.debug('WARNING: Stage_Weight__c is required by metadata, so B8 blank weight is created as 0.');
        }
    }

    if (
        stageFields.containsKey('Stage_Order__c') &&
        stageFields.get('Stage_Order__c').getDescribe().isCreateable()
    ) {
        st.put('Stage_Order__c', orderNumber);
    }

    if (
        stageFields.containsKey('Stage_Number__c') &&
        stageFields.get('Stage_Number__c').getDescribe().isCreateable()
    ) {
        st.put('Stage_Number__c', orderNumber);
    }

    if (
        stageFields.containsKey('Minimum_Score__c') &&
        stageFields.get('Minimum_Score__c').getDescribe().isCreateable()
    ) {
        st.put('Minimum_Score__c', 10);
    }

    if (
        stageFields.containsKey('Passing_Threshold__c') &&
        stageFields.get('Passing_Threshold__c').getDescribe().isCreateable()
    ) {
        st.put('Passing_Threshold__c', 10);
    }

    if (
        stageFields.containsKey('Maximum_Score__c') &&
        stageFields.get('Maximum_Score__c').getDescribe().isCreateable()
    ) {
        st.put('Maximum_Score__c', 20);
    }

    if (
        stageFields.containsKey('Max_Score__c') &&
        stageFields.get('Max_Score__c').getDescribe().isCreateable()
    ) {
        st.put('Max_Score__c', 20);
    }

    // IMPORTANT:
    // Keep stages inactive for test data.
    // Your org has a validation rule:
    // "An Interview Stage must have at least one team member before it can be activated."
    if (
        stageFields.containsKey('Is_Active__c') &&
        stageFields.get('Is_Active__c').getDescribe().isCreateable()
    ) {
        st.put('Is_Active__c', false);
    }

    if (
        stageFields.containsKey('Start_Date__c') &&
        stageFields.get('Start_Date__c').getDescribe().isCreateable()
    ) {
        st.put('Start_Date__c', Date.today());
    }

    if (
        stageFields.containsKey('End_Date__c') &&
        stageFields.get('End_Date__c').getDescribe().isCreateable()
    ) {
        st.put('End_Date__c', Date.today().addDays(30));
    }

    if (
        stageFields.containsKey('Stage_Type__c') &&
        stageFields.get('Stage_Type__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            stageFields.get('Stage_Type__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            st.put('Stage_Type__c', vals[0].getValue());
        }
    }

    stagesToInsert.add(st);
}

insert stagesToInsert;

System.debug('Created Interview Stages: ' + stagesToInsert.size());

// Optional: create one related application for E1_OPEN_CANCEL.
if (gd.containsKey('Candidate__c') && gd.containsKey('Job_Application__c')) {
    Schema.SObjectType candidateType = gd.get('Candidate__c');
    Schema.SObjectType applicationType = gd.get('Job_Application__c');

    Map<String, Schema.SObjectField> candidateFields =
        candidateType.getDescribe().fields.getMap();

    Map<String, Schema.SObjectField> applicationFields =
        applicationType.getDescribe().fields.getMap();

    SObject candidate = candidateType.newSObject();

    if (
        candidateFields.containsKey('Name') &&
        candidateFields.get('Name').getDescribe().isCreateable()
    ) {
        candidate.put('Name', 'TF009 Cancel Test Candidate');
    }

    if (
        candidateFields.containsKey('FirstName__c') &&
        candidateFields.get('FirstName__c').getDescribe().isCreateable()
    ) {
        candidate.put('FirstName__c', 'TF009');
    }

    if (
        candidateFields.containsKey('LastName__c') &&
        candidateFields.get('LastName__c').getDescribe().isCreateable()
    ) {
        candidate.put('LastName__c', 'Cancel Test');
    }

    if (
        candidateFields.containsKey('Email__c') &&
        candidateFields.get('Email__c').getDescribe().isCreateable()
    ) {
        candidate.put('Email__c', 'tf009.cancel.' + DateTime.now().getTime() + '@example.com');
    }

    if (
        candidateFields.containsKey('Phone__c') &&
        candidateFields.get('Phone__c').getDescribe().isCreateable()
    ) {
        candidate.put('Phone__c', '0600' + String.valueOf(Math.mod(DateTime.now().getTime(), 1000000)));
    }

    if (
        candidateFields.containsKey('Journey_Status__c') &&
        candidateFields.get('Journey_Status__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            candidateFields.get('Journey_Status__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            candidate.put('Journey_Status__c', vals[0].getValue());
        }
    }

    insert candidate;

    SObject application = applicationType.newSObject();

    if (
        applicationFields.containsKey('Name') &&
        applicationFields.get('Name').getDescribe().isCreateable()
    ) {
        application.put('Name', 'TF009 Cancel Related Application');
    }

    if (
        applicationFields.containsKey('Candidate__c') &&
        applicationFields.get('Candidate__c').getDescribe().isCreateable()
    ) {
        application.put('Candidate__c', candidate.get('Id'));
    }

    if (
        applicationFields.containsKey('Job_Position__c') &&
        applicationFields.get('Job_Position__c').getDescribe().isCreateable()
    ) {
        application.put('Job_Position__c', positionIdsByKey.get('E1_OPEN_CANCEL'));
    }

    if (
        applicationFields.containsKey('Stage__c') &&
        applicationFields.get('Stage__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            applicationFields.get('Stage__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            application.put('Stage__c', vals[0].getValue());
        }
    }

    if (
        applicationFields.containsKey('Selection_Status__c') &&
        applicationFields.get('Selection_Status__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            applicationFields.get('Selection_Status__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            application.put('Selection_Status__c', vals[0].getValue());
        }
    }

    if (
        applicationFields.containsKey('Application_Type__c') &&
        applicationFields.get('Application_Type__c').getDescribe().isCreateable()
    ) {
        List<Schema.PicklistEntry> vals =
            applicationFields.get('Application_Type__c').getDescribe().getPicklistValues();

        if (!vals.isEmpty()) {
            application.put('Application_Type__c', vals[0].getValue());
        }
    }

    insert application;

    System.debug('Created related Job Application for cancel test: ' + application.get('Id'));
}

System.debug('========== TF-009 TEST DATA CREATED ==========');
System.debug('Open each Job Position by searching for records starting with TF009.');
System.debug('Position Ids by case: ' + positionIdsByKey);