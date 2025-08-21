@IsTest
private class JobApplicationCloseStaleBatchTest {

    @testSetup
    static void setupData() {
        List<Job_Application__c> apps = new List<Job_Application__c>();

        // Stale record (should be closed by batch)
        apps.add(new Job_Application__c(
            Status__c = 'Interviewing',
            Follow_Up_Date__c = Date.today().addDays(-40),
            Notes__c = 'Initial notes'
        ));

        // Recent record (should not be touched)
        apps.add(new Job_Application__c(
            Status__c = 'Interviewing',
            Follow_Up_Date__c = Date.today().addDays(-5),
            Notes__c = 'Recent notes'
        ));

        // Already Closed record (should be ignored by query)
        apps.add(new Job_Application__c(
            Status__c = 'Closed',
            Follow_Up_Date__c = Date.today().addDays(-60),
            Notes__c = 'Already closed'
        ));

        insert apps;
    }

    @IsTest
    static void testBatchExecution() {
        Test.startTest();
        // Run batch with small scope size to test logic
        Database.executeBatch(new JobApplicationCloseStaleBatch(), 1);
        Test.stopTest();

        // Verify results
        List<Job_Application__c> results = [
            SELECT Status__c, Notes__c, Follow_Up_Date__c
            FROM Job_Application__c
            ORDER BY CreatedDate
        ];

        System.assertEquals('Closed', results[0].Status__c, 'Stale record should be closed');
        System.assert(results[0].Notes__c.contains('Auto-Closure'), 'Notes should include auto-closure text');

        System.assertEquals('Interviewing', results[1].Status__c, 'Recent record should not be closed');
        System.assert(!results[1].Notes__c.contains('Auto-Closure'), 'Recent record should not be updated');

        System.assertEquals('Closed', results[2].Status__c, 'Already closed record should stay closed');
    }

    @IsTest
    static void testSchedulableExecution() {
        Test.startTest();
        System.schedule('Test Schedule', '0 0 12 * * ?', new JobApplicationCloseStaleBatch());
        Test.stopTest();

        // After schedule runs, the batch will have been executed, but
        // the coverage is from invoking the schedulable entry point
        // since Database.executeBatch is already tested above.
    }
}
