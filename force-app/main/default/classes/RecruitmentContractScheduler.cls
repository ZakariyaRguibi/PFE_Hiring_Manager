global class RecruitmentContractScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        RecruitmentHiringService.expireUnsignedContracts();
    }
}