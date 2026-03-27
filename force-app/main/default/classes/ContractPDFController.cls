public without sharing class ContractPDFController {

    public Contract contract { get; set; }
    public Opportunity opportunity { get; set; }
    public Account account { get; set; }

    public ContractPDFController() {
        String contractId = ApexPages.currentPage().getParameters().get('contractId');
        String oppId = ApexPages.currentPage().getParameters().get('oppId');

        if (String.isNotBlank(contractId)) {
            contract = [
                SELECT Id, ContractNumber, StartDate, Status, Deadline__c
                FROM Contract
                WHERE Id = :contractId
                LIMIT 1
            ];
        }

        if (String.isNotBlank(oppId)) {
            opportunity = [
                SELECT Id, Name, AccountId, Job_Position__r.Name
                FROM Opportunity
                WHERE Id = :oppId
                LIMIT 1
            ];

            if (opportunity.AccountId != null) {
                account = [
                    SELECT Id, Name, PersonEmail
                    FROM Account
                    WHERE Id = :opportunity.AccountId
                    LIMIT 1
                ];
            }
        }
    }
}