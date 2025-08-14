public with sharing class JobApplicationContactTriggerHandler {
    public static void run(Boolean isInsert, Boolean isUpdate, List<Job_Application_Contact__c> newList, Map<Id, Job_Application_Contact__c> oldMap) {
        // Create set to track job app Ids that may need primary contact
        Set<Id> jobAppIdsToCheck = new Set<Id>();

        // If insert for each job app contact record see if job app id is populated and add to set
        if (isInsert) {
            for (Job_Application_Contact__c jac : newList) {
                if (jac.Job_Application__c != null) {
                    jobAppIdsToCheck.add(jac.Job_Application__c);
                }
            }
        }
        // If update for each JAC compare old job app Id to new job app Id if different add to set
        if (isUpdate) {
            for (Job_Application_Contact__c jac : newList) {
                Job_Application_Contact__c oldJac = oldMap.get(jac.Id);
                if (jac.Job_Application__c != oldJac.Job_Application__c && jac.Job_Application__c != null) {
                    jobAppIdsToCheck.add(jac.Job_Application__c);
                }
            }
        }
        if (!jobAppIdsToCheck.isEmpty()) {
            // Query job apps that are missing primary contact
            List<Job_Application__c> appsToCheck = [
                SELECT Id, Primary_Contact__c, Company_Name__c
                FROM Job_Application__c
                WHERE Id IN :jobAppIdsToCheck AND Primary_Contact__c = null
            ];

            JobApplicationPrimaryContactSetter.setPrimaryContacts(appsToCheck);
        }
    }
}