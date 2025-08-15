public class JobApplicationTriggerHandler {
    // Handler uses booleans from trigger to choose path
    public static void run(Boolean isBefore, Boolean isAfter, Boolean isInsert, Boolean isUpdate) {
        List<Job_Application__c> newApps = (List<Job_Application__c>) Trigger.new;

        if (isAfter && isInsert) {
            JobApplicationTaskCreation.createTasksForApplications((List<Job_Application__c>) newApps, null);

            List<Job_Application__c> appsToCheck = getWritableJobApplications(newApps);
            JobApplicationPrimaryContactSetter.setPrimaryContacts(appsToCheck);
        }

        if (isAfter && isUpdate) {
            JobApplicationTaskCreation.createTasksForApplications(newApps,(Map<Id, Job_Application__c>) Trigger.oldMap);
            
            List<Job_Application__c> appsToCheck = getWritableJobApplications(newApps);
            JobApplicationPrimaryContactSetter.setPrimaryContacts(appsToCheck);
        }
    }

    private static List<Job_Application__c> getWritableJobApplications(List<Job_Application__c> apps) {
        Set<Id> jobAppIds = new Set<Id>();
        for (Job_Application__c app : apps) {
            jobAppIds.add(app.id);
        }

        return [
            SELECT Id, Primary_Contact__c, Company_Name__c
            FROM Job_Application__c
            WHERE Id IN :jobAppIds
        ];
    }
}