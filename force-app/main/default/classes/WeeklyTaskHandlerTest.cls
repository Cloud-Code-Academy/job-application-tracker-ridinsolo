@IsTest 
private class WeeklyTaskHandlerTest {
    // Build a job application
    private static Job_Application__c makeApp(String name, String Status) {
        Job_Application__c app = new Job_Application__c();
        app.name = name;
        app.Status__c = status;
        return app;
    }

    @IsTest 
    static void testAfterUpdate_bulkAndFilters() {
        // Test data
        Job_Application__c appApplied = makeApp('App Applied', 'Applied');
        Job_Application__c appNotApplied = makeApp('App Not Applied', 'Interviewing');
        insert new List<Job_Application__c>{appApplied, appNotApplied};

        String weeklySubject = JobApplicationTaskCreation.WEEKLY_TAG + ' Follow up weekly';
        Id ownerId = UserInfo.getUserId();

        // Task1 Weekly on Applied app will be closed, should create new weekly task
        Task t1 = new Task( 
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weeklySubject,
            Priority = 'High',
            IsClosed = false
        );
        // t2: Weekly on Applied app, will be closed, but there is already an open duplicate => should NOT create
        Task t2 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weeklySubject,
            Priority = 'Normal',
            IsClosed = false
        );

        // Open duplicate for t2 key (WhatId+OwnerId+Subject) so handler should skip creating another
        Task openDup = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weeklySubject,
            Priority = 'Normal',
            IsClosed = false
        );

        // t3: Weekly but parent app is not Applied => should NOT create
        Task t3 = new Task(
            WhatId = appNotApplied.Id,
            OwnerId = ownerId,
            Subject = weeklySubject,
            Priority = 'Normal',
            IsClosed = false
        );

        // t4: Non‑weekly subject on Applied app => should NOT create
        Task t4 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = 'Regular follow up',
            Priority = 'Normal',
            IsClosed = false
        );

        // t5: Weekly on Applied app but already closed before the update (no open→closed transition) => should NOT create
        Task t5 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weeklySubject,
            Priority = 'Low',
            IsClosed = true
        );

        insert new List<Task>{ t1, t2, openDup, t3, t4, t5 };

        // Build oldMap as the "before update" snapshot
        Map<Id, Task> oldMap = new Map<Id, Task>([
            SELECT Id, WhatId, OwnerId, Subject, Priority, IsClosed
            FROM Task
            WHERE Id IN :new List<Id>{ t1.Id, t2.Id, openDup.Id, t3.Id, t4.Id, t5.Id }
        ]);

        // Perform the real updates that would fire the after update context
        // t1, t2, t3, t4 will transition to IsClosed=true
        t1.IsClosed = true;
        t2.IsClosed = true;
        t3.IsClosed = true;
        t4.IsClosed = true;

        // t5 stays closed but change something else so it is included in the newList
        t5.Priority = 'High';

        List<Task> updated = new List<Task>{ t1, t2, t3, t4, t5 };
        update updated;

        Test.startTest();
        // Call the handler directly to simulate an after update trigger
        WeeklyTaskHandler.afterUpdate(updated, oldMap);
        Test.stopTest();

        // Gather tasks again to assert results
        Date expectedNextDue = Date.today().addDays(7);

        // All open weekly tasks on the Applied app with the weeklySubject
        List<Task> resultingOpenWeeklies = [
            SELECT Id, WhatId, OwnerId, Subject, Priority, IsClosed, ActivityDate
            FROM Task
            WHERE IsClosed = false
              AND WhatId = :appApplied.Id
              AND OwnerId = :ownerId
              AND Subject = :weeklySubject
        ];

        // We inserted exactly one open duplicate before the handler ran.
        // The handler should add exactly one more (for t1) and skip t2 due to duplicate, skip t3/t4/t5 due to filters.
        // So total should be 2 (the original openDup plus the newly created "next week" task for t1).
        System.assertEquals(2, resultingOpenWeeklies.size(),
            'There should be exactly one newly created open weekly task in addition to the original open duplicate.');

        // Find the newly created task by due date = today+7 (the openDup has no enforced due date in setup)
        Task created = null;
        for (Task t : resultingOpenWeeklies) {
            if (t.ActivityDate == expectedNextDue) {
                created = t;
                break;
            }
        }
        System.assertNotEquals(null, created, 'A next weekly task due in 7 days should have been created for t1.');

        // Validate fields copied from the closed weekly task (t1)
        System.assertEquals(appApplied.Id, created.WhatId, 'WhatId should match the closed task parent.');
        System.assertEquals(ownerId, created.OwnerId, 'OwnerId should be preserved.');
        System.assertEquals(weeklySubject, created.Subject, 'Subject should match the closed weekly task.');
        System.assertEquals('High', created.Priority, 'Priority should be copied from the closed weekly task.');
        System.assertEquals(expectedNextDue, created.ActivityDate, 'Next weekly task should be due 7 days from today.');

        // Negative checks: nothing new created for the non‑Applied app
        Integer nonAppliedNew = [
            SELECT COUNT() FROM Task
            WHERE IsClosed = false
              AND WhatId = :appNotApplied.Id
              AND Subject = :weeklySubject
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(0, nonAppliedNew, 'No weekly task should be created when parent status is not Applied.');

        // Negative checks: nothing created for non‑weekly subject
        Integer nonWeeklyNew = [
            SELECT COUNT() FROM Task
            WHERE IsClosed = false
              AND WhatId = :appApplied.Id
              AND Subject = 'Regular follow up'
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(0, nonWeeklyNew, 'Non‑weekly subjects should not produce new tasks.');
    }

    @IsTest
    static void testAfterUpdate_emptyInputs() {
        Test.startTest();
        WeeklyTaskHandler.afterUpdate(new List<Task>(), new Map<Id, Task>());
        Test.stopTest();
        // No exceptions is the assertion
        System.assert(true, 'Handler should safely handle empty inputs.');
    }
}
