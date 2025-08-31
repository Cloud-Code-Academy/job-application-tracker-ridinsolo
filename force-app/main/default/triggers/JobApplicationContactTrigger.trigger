trigger JobApplicationContactTrigger on Job_Application_Contact__c (after insert, after update) {
    JobApplicationContactTriggerHandler.run(Trigger.isInsert, Trigger.isUpdate, Trigger.new, Trigger.oldMap);
}