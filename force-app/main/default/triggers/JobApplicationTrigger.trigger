trigger JobApplicationTrigger on Job_Application__c (after insert, after update) {
    // Trigger passes four booleans to the handler
    JobApplicationTriggerHandler.run(Trigger.isBefore, Trigger.isAfter, Trigger.isInsert, Trigger.isUpdate);
}