public class JobApplicationTriggerHandler {
    // Handler uses booleans from trigger to choose path
    public static void run(Boolean isBefore, Boolean isAfter, Boolean isInsert, Boolean isUpdate) {
        if (isAfter && isInsert) {
            JobApplicationTaskCreation.createTasksForApplications(
                (List<Job_Application__c>) Trigger.new, null
                );
        }
        if (isAfter && isUpdate) {
            JobApplicationTaskCreation.createTasksForApplications(
                (List<Job_Application__c>) Trigger.new,
                (Map<Id, Job_Application__c>) Trigger.oldMap
                );
        }
    }
}