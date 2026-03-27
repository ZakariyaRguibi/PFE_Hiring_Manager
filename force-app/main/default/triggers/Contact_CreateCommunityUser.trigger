trigger Contact_CreateCommunityUser on Contact (after insert, after update) {

    Set<Id> contactsToProcess = new Set<Id>();

    for(Contact c : Trigger.new){

        if(c.Email != null && c.AccountId != null){

            if(Trigger.isInsert){
                contactsToProcess.add(c.Id);
            }

            if(Trigger.isUpdate){
                Contact oldC = Trigger.oldMap.get(c.Id);

                if(oldC.Email == null && c.Email != null){
                    contactsToProcess.add(c.Id);
                }
            }
        }
    }

    if(!contactsToProcess.isEmpty()){
        System.enqueueJob(new CandidateCommunityUserProvisioner(contactsToProcess));
    }

}