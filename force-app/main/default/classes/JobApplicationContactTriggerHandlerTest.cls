@IsTest
private class JobApplicationContactTriggerHandlerTest {

    private static Account makeAcct(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    private static Contact makeContact(String lastName) {
        Contact c = new Contact(LastName = lastName);
        insert c;
        return c;
    }

    // Creates a Job Application with required fields only
    private static Job_Application__c makeJobApp(String companyName) {
        Account a = makeAcct(companyName);
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = a.Id
            // Add other required fields for your org here
        );
        insert app; // This DML will fire JobApplicationTrigger (after insert)
        return app;
    }

    // Overload that also sets Status__c to exercise status-based task creation in the trigger
    private static Job_Application__c makeJobApp(String companyName, String status) {
        Account a = makeAcct(companyName);
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = a.Id,
            Status__c = status
        );
        insert app; // Fires JobApplicationTrigger (after insert)
        return app;
    }

    private static Job_Application_Contact__c makeJac(Id appId, Id contactId) {
        Job_Application_Contact__c jac = new Job_Application_Contact__c(
            Job_Application__c = appId,
            Contact__c = contactId
        );
        insert jac;
        return jac;
    }

    @IsTest
    static void testInsert_setsPrimaryContactWhenMissing() {
        Job_Application__c app = makeJobApp('Acme Corp');
        Contact c = makeContact('InsertPath');

        Job_Application_Contact__c jac = makeJac(app.Id, c.Id);

        // Simulate after-insert on JAC handler
        List<Job_Application_Contact__c> newList = [
            SELECT Id, Job_Application__c
            FROM Job_Application_Contact__c
            WHERE Id = :jac.Id
        ];
        JobApplicationContactTriggerHandler.run(true, false, newList, new Map<Id, Job_Application_Contact__c>());

        Job_Application__c refreshed = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(c.Id, refreshed.Primary_Contact__c, 'Primary contact should be set from the inserted JAC.');
    }

    @IsTest
    static void testUpdate_movesJacAndSetsPrimaryOnNewApp() {
        Job_Application__c appA = makeJobApp('OldCo');
        Job_Application__c appB = makeJobApp('NewCo');
        Contact c = makeContact('UpdatePath');

        Job_Application_Contact__c jac = makeJac(appA.Id, c.Id);

        // Capture oldMap state
        Job_Application_Contact__c oldJac = jac.clone(false, true, false, false); // preserve Id

        // Change the JAC to point at appB
        jac.Job_Application__c = appB.Id;
        update jac;

        List<Job_Application_Contact__c> newList = [
            SELECT Id, Job_Application__c
            FROM Job_Application_Contact__c
            WHERE Id = :jac.Id
        ];
        Map<Id, Job_Application_Contact__c> oldMap = new Map<Id, Job_Application_Contact__c>{ jac.Id => oldJac };

        JobApplicationContactTriggerHandler.run(false, true, newList, oldMap);

        Job_Application__c refreshedB = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :appB.Id
        ];
        System.assertEquals(c.Id, refreshedB.Primary_Contact__c, 'New app should receive primary contact after update.');

        Job_Application__c refreshedA = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :appA.Id
        ];
        System.assertEquals(null, refreshedA.Primary_Contact__c, 'Original app should remain unchanged.');
    }

    @IsTest
    static void testNoop_whenPrimaryAlreadySetOrNoApp() {
        Job_Application__c app = makeJobApp('AlreadyHasPrimary');

        Contact original = makeContact('ExistingPrimary');
        app.Primary_Contact__c = original.Id;
        update app;

        Contact other = makeContact('Other');
        Job_Application_Contact__c jac = makeJac(app.Id, other.Id);

        Job_Application_Contact__c jacNoApp = new Job_Application_Contact__c(Contact__c = other.Id);
        insert jacNoApp;

        List<Job_Application_Contact__c> newList = [
            SELECT Id, Job_Application__c
            FROM Job_Application_Contact__c
            WHERE Id IN :new Set<Id>{ jac.Id, jacNoApp.Id }
        ];
        JobApplicationContactTriggerHandler.run(true, false, newList, new Map<Id, Job_Application_Contact__c>());

        Job_Application__c refreshed = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(original.Id, refreshed.Primary_Contact__c, 'Apps with an existing primary should be skipped.');
    }

    // New: covers JobApplicationTrigger on after insert
    @IsTest
    static void testJobApplicationTrigger_afterInsert_createsTasks() {
        // Use a status that your JobApplicationTaskCreation maps, e.g., 'Saved'
        Job_Application__c app = makeJobApp('TriggerInsertCo', 'Saved'); // insert fires trigger (after insert)

        // Minimal assertion that some tasks were created for this application
        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :app.Id
        ];
        System.assert(taskCount > 0, 'After-insert trigger should create at least one task for status Saved.');
    }

    // New: covers JobApplicationTrigger on after update and exercises primary contact setter from the trigger path
    @IsTest
    static void testJobApplicationTrigger_afterUpdate_setsPrimaryAndMayCreateTasks() {
        // Start with a status that maps to tasks, then change it to a different mapped status
        Job_Application__c app = makeJobApp('TriggerUpdateCo', 'Saved');

        // Create a JAC so when we update the app, the trigger path that calls JobApplicationPrimaryContactSetter can set Primary_Contact__c
        Contact c = makeContact('TriggerUpdateContact');
        makeJac(app.Id, c.Id);

        // Update the app to fire after update path
        app.Status__c = 'Applying';
        update app; // fires JobApplicationTrigger (after update)

        // Assert primary contact set by the handler invoked from the trigger
        Job_Application__c refreshed = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :app.Id
        ];
        System.assertEquals(c.Id, refreshed.Primary_Contact__c, 'After-update trigger should set Primary_Contact__c when a JAC exists.');

        // Optional light check that additional tasks may have been created on update
        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :app.Id
        ];
        System.assert(taskCount > 0, 'After-update trigger should leave at least one task associated to the application.');
    }
}

