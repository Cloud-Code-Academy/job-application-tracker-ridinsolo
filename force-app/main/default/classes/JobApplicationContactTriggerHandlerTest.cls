@IsTest
private class JobApplicationContactTriggerHandlerTest {

    // Utility to create a Contact used by Job Application Contact records later
    private static Contact createContact(String lastName) {
        Contact c = new Contact(LastName = lastName);
        insert c;
        return c;
    }

    // Utility to create a Job Application. 
    // Note: if your org has required fields on Job_Application__c, set them here.
    private static Job_Application__c createJobApp(String companyName) {
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = companyName
            // Set any other required fields for your org here
        );
        insert app;
        return app;
    }

    // Creates a Job_Application_Contact__c linking a Job Application and a Contact
    private static Job_Application_Contact__c createJac(Id appId, Id contactId) {
        Job_Application_Contact__c jac = new Job_Application_Contact__c(
            Job_Application__c = appId,
            Contact__c = contactId
        );
        insert jac;
        return jac;
    }

    @IsTest
    static void testInsert_setsPrimaryContactWhenMissing() {
        // Arrange: create a job app with no primary contact yet
        Job_Application__c app = createJobApp('Acme Corp');
        Contact c = createContact('InsertPath');

        // Create JAC records that will be passed as Trigger.new later
        Job_Application_Contact__c jac = new Job_Application_Contact__c(
            Job_Application__c = app.Id,
            Contact__c = c.Id
        );

        // We "simulate" an after-insert trigger run by inserting and then calling handler
        insert jac;

        // Act: call the handler with isInsert = true, isUpdate = false
        List<Job_Application_Contact__c> newList = [SELECT Id, Job_Application__c FROM Job_Application_Contact__c WHERE Id = :jac.Id];
        Map<Id, Job_Application_Contact__c> emptyOldMap = new Map<Id, Job_Application_Contact__c>();
        JobApplicationContactTriggerHandler.run(true, false, newList, emptyOldMap);

        // Assert: the job application's Primary_Contact__c should now be set (setter chooses from JACs)
        Job_Application__c refreshed = [
            SELECT Id, Primary_Contact__c
            FROM Job_Application__c
            WHERE Id = :app.Id
        ];
        System.assertNotEquals(null, refreshed.Primary_Contact__c, 'Primary_Contact__c should be set after insert handler runs.');
        System.assertEquals(c.Id, refreshed.Primary_Contact__c, 'Primary_Contact__c should be set to the JAC’s Contact.');
    }

    @IsTest
    static void testUpdate_movesJacAndSetsPrimaryOnNewApp() {
        // Arrange: create two apps; appA remains unchanged, appB should get a primary
        Job_Application__c appA = createJobApp('OldCo');
        Job_Application__c appB = createJobApp('NewCo');
        Contact c = createContact('UpdatePath');

        // Start with JAC pointing to appA
        Job_Application_Contact__c jac = createJac(appA.Id, c.Id);

        // Simulate Trigger.oldMap by capturing the prior state before the change
        Job_Application_Contact__c oldJac = jac.clone(false, true, false, false);
        // oldJac.Job_Application__c = appA.Id (already set)

        // Now "update" the JAC to point to appB (this is what the trigger would see in Trigger.new)
        jac.Job_Application__c = appB.Id;
        update jac;

        // Build params to simulate after update trigger
        List<Job_Application_Contact__c> newList = [
            SELECT Id, Job_Application__c FROM Job_Application_Contact__c WHERE Id = :jac.Id
        ];
        Map<Id, Job_Application_Contact__c> oldMap = new Map<Id, Job_Application_Contact__c>{ jac.Id => oldJac };

        // Act: call the handler with isInsert = false, isUpdate = true
        JobApplicationContactTriggerHandler.run(false, true, newList, oldMap);

        // Assert: appB should now have a primary contact set
        Job_Application__c refreshedB = [
            SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :appB.Id
        ];
        System.assertEquals(c.Id, refreshedB.Primary_Contact__c, 'Update path should set primary on the new Job Application.');

        // Also assert appA remains as-is (still null unless your setter alters it)
        Job_Application__c refreshedA = [
            SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :appA.Id
        ];
        System.assertEquals(null, refreshedA.Primary_Contact__c, 'Original Job Application should not gain a primary from this update path.');
    }

    @IsTest
    static void testNoop_whenPrimaryAlreadySetOrNoApp() {
        // Arrange: app with a primary already set should be skipped by WHERE Primary_Contact__c = null
        Job_Application__c app = createJobApp('AlreadyHasPrimary');
        Contact original = createContact('ExistingPrimary');
        app.Primary_Contact__c = original.Id;
        update app;

        // Create a JAC pointing at this app
        Contact other = createContact('Other');
        Job_Application_Contact__c jac = createJac(app.Id, other.Id);

        // Add another JAC with null Job_Application__c to prove nulls are ignored
        Job_Application_Contact__c jacNoApp = new Job_Application_Contact__c(Contact__c = other.Id);
        insert jacNoApp;

        // Act: run the insert path with both rows
        List<Job_Application_Contact__c> newList = [
            SELECT Id, Job_Application__c FROM Job_Application_Contact__c WHERE Id IN :new Set<Id>{ jac.Id, jacNoApp.Id }
        ];
        JobApplicationContactTriggerHandler.run(true, false, newList, new Map<Id, Job_Application_Contact__c>());

        // Assert: primary should remain the original because handler filters apps with Primary_Contact__c = null
        Job_Application__c refreshed = [
            SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals(original.Id, refreshed.Primary_Contact__c, 'Handler should not touch apps that already have a primary contact.');
    }
}
