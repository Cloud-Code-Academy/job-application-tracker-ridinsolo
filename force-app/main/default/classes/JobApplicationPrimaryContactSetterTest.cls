@IsTest
private class JobApplicationPrimaryContactSetterTest {

    // Utility method to create a basic Account and Contact
    private static Contact createContactWithAccount(String acctName, String contactName) {
        Account acct = new Account(Name = acctName);
        insert acct;

        Contact c = new Contact(FirstName = contactName, LastName = 'Test', AccountId = acct.Id);
        insert c;
        return c;
    }

    @IsTest
    static void testPrimaryContactFromJobApplicationContact() {
        // Create a Contact to use
        Contact c = createContactWithAccount('Test Account 1', 'Alpha');

        // Create Job Application with no primary contact
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = c.AccountId
        );
        insert app;

        // Create related Job Application Contact
        Job_Application_Contact__c jac = new Job_Application_Contact__c(
            Job_Application__c = app.Id,
            Contact__c = c.Id
        );
        insert jac;

        // Call method
        Test.startTest();
        JobApplicationPrimaryContactSetter.setPrimaryContacts(new List<Job_Application__c>{app});
        Test.stopTest();

        // Re-query to check update
        app = [SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :app.Id];
        System.assertEquals(c.Id, app.Primary_Contact__c, 'Primary contact should be set from Job Application Contact');
    }

    @IsTest
    static void testPrimaryContactFromAccountFallback() {
        // Create a Contact tied to an Account
        Contact c = createContactWithAccount('Test Account 2', 'Beta');

        // Create Job Application with no primary contact and NO Job Application Contact
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = c.AccountId
        );
        insert app;

        // Call method
        Test.startTest();
        JobApplicationPrimaryContactSetter.setPrimaryContacts(new List<Job_Application__c>{app});
        Test.stopTest();

        // Re-query to check update
        app = [SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :app.Id];
        System.assertEquals(c.Id, app.Primary_Contact__c, 'Primary contact should be set from related Account contact');
    }

    @IsTest
    static void testNoUpdateWhenPrimaryExists() {
        Contact c = createContactWithAccount('Test Account 3', 'Gamma');

        // Create Job Application that already has a Primary Contact
        Job_Application__c app = new Job_Application__c(
            Company_Name__c = c.AccountId,
            Primary_Contact__c = c.Id
        );
        insert app;

        // Call method
        Test.startTest();
        JobApplicationPrimaryContactSetter.setPrimaryContacts(new List<Job_Application__c>{app});
        Test.stopTest();

        // Ensure it was unchanged
        app = [SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :app.Id];
        System.assertEquals(c.Id, app.Primary_Contact__c, 'Primary contact should not change if already set');
    }

    @IsTest
    static void testNoContactsNoFallback() {
        // Create Account with NO contacts
        Account acct = new Account(Name = 'Empty Account');
        insert acct;

        Job_Application__c app = new Job_Application__c(
            Company_Name__c = acct.Id
        );
        insert app;

        // Call method
        Test.startTest();
        JobApplicationPrimaryContactSetter.setPrimaryContacts(new List<Job_Application__c>{app});
        Test.stopTest();

        // Check that no primary contact was set
        app = [SELECT Id, Primary_Contact__c FROM Job_Application__c WHERE Id = :app.Id];
        System.assertEquals(null, app.Primary_Contact__c, 'Primary contact should remain null if no related contacts exist');
    }
}
