@IsTest
private class WeeklyTaskHandlerTest {
    // Get an open status (not closed) and a closed status (e.g., Completed) from org config
    private static String getOpenStatus() {
        List<TaskStatus> openStatuses = [
            SELECT MasterLabel, IsClosed, IsDefault
            FROM TaskStatus
            WHERE IsClosed = false
            ORDER BY IsDefault DESC, MasterLabel
            LIMIT 1
        ];
        System.assert(!openStatuses.isEmpty(), 'No open TaskStatus found.');
        return openStatuses[0].MasterLabel;
    }
    private static String getClosedStatus() {
        List<TaskStatus> closedStatuses = [
            SELECT MasterLabel, IsClosed
            FROM TaskStatus
            WHERE IsClosed = true
            LIMIT 1
        ];
        System.assert(!closedStatuses.isEmpty(), 'No closed TaskStatus found.');
        return closedStatuses[0].MasterLabel;
    }

    private static Job_Application__c makeApp(String status) {
        Job_Application__c app = new Job_Application__c(
            Status__c = status
        );
        insert app;
        return app;
    }

    @IsTest
    static void testAfterUpdate_bulkAndFilters() {
        // Arrange
        String openStatus = getOpenStatus();
        String closedStatus = getClosedStatus();

        Job_Application__c appApplied = makeApp('Applied');
        Job_Application__c appNotApplied = makeApp('Interviewing');

        Id ownerId = UserInfo.getUserId();
        String weekly1 = JobApplicationTaskCreation.WEEKLY_TAG + ' Follow up weekly';
        String weekly2 = JobApplicationTaskCreation.WEEKLY_TAG + ' Check progress';
        String nonWeekly = 'Regular follow up';

        // t1: weekly1 on Applied app, will be closed => should create a new weekly task
        Task t1 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weekly1,
            Priority = 'High',
            Status = openStatus
        );
        // t2: weekly2 on Applied app, will be closed, but an open duplicate exists => should NOT create
        Task t2 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weekly2,
            Priority = 'Normal',
            Status = openStatus
        );
        // Open duplicate for t2 key (WhatId+OwnerId+Subject)
        Task openDup = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weekly2,
            Priority = 'Normal',
            Status = openStatus
        );
        // t3: weekly on Not Applied app => should NOT create
        Task t3 = new Task(
            WhatId = appNotApplied.Id,
            OwnerId = ownerId,
            Subject = weekly1,
            Priority = 'Normal',
            Status = openStatus
        );
        // t4: non-weekly on Applied app => should NOT create
        Task t4 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = nonWeekly,
            Priority = 'Normal',
            Status = openStatus
        );
        // t5: weekly already closed before the update => should NOT create (no open→closed transition)
        Task t5 = new Task(
            WhatId = appApplied.Id,
            OwnerId = ownerId,
            Subject = weekly1,
            Priority = 'Low',
            Status = closedStatus
        );

        insert new List<Task>{ t1, t2, openDup, t3, t4, t5 };

        // Old map snapshot before we flip statuses
        Map<Id, Task> oldMap = new Map<Id, Task>([
            SELECT Id, WhatId, OwnerId, Subject, Priority, Status, IsClosed
            FROM Task
            WHERE Id IN :new List<Id>{ t1.Id, t2.Id, openDup.Id, t3.Id, t4.Id, t5.Id }
        ]);

        // Act: flip some tasks to a closed status to trigger the logic
        t1.Status = closedStatus;
        t2.Status = closedStatus;
        t3.Status = closedStatus;
        t4.Status = closedStatus;
        // Keep t5 closed, but touch a non-status field so it appears in newList
        t5.Priority = 'High';
        update new List<Task>{ t1, t2, t3, t4, t5 };

        // Re-query to get computed IsClosed values for the "after update" list
        List<Task> newList = [
            SELECT Id, WhatId, OwnerId, Subject, Priority, Status, IsClosed, ActivityDate
            FROM Task
            WHERE Id IN :new List<Id>{ t1.Id, t2.Id, t3.Id, t4.Id, t5.Id }
        ];

        Test.startTest();
        WeeklyTaskHandler.afterUpdate(newList, oldMap);
        Test.stopTest();

        // Assert
        Date expectedNextDue = Date.today().addDays(7);

        // For weekly1 on Applied app: exactly one new open task due today+7 should be created
        List<Task> weekly1Open = [
            SELECT Id, WhatId, OwnerId, Subject, ActivityDate, IsClosed, Priority
            FROM Task
            WHERE IsClosed = false
              AND WhatId = :appApplied.Id
              AND OwnerId = :ownerId
              AND Subject = :weekly1
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(1, weekly1Open.size(),
            'One next weekly task should be created for weekly1 on the Applied app.');
        Task created = weekly1Open[0];
        System.assertEquals('High', created.Priority, 'Priority should carry over from the closed task.');

        // For weekly2 on Applied app: none created because an open duplicate already existed
        Integer weekly2Created = [
            SELECT COUNT() FROM Task
            WHERE IsClosed = false
              AND WhatId = :appApplied.Id
              AND OwnerId = :ownerId
              AND Subject = :weekly2
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(0, weekly2Created,
            'No new task should be created for weekly2 because an open duplicate exists.');

        // No creations for non-Applied app
        Integer notAppliedCount = [
            SELECT COUNT() FROM Task
            WHERE IsClosed = false
              AND WhatId = :appNotApplied.Id
              AND Subject = :weekly1
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(0, notAppliedCount,
            'No weekly task should be created when parent status is not Applied.');

        // No creations for non-weekly subject
        Integer nonWeeklyCount = [
            SELECT COUNT() FROM Task
            WHERE IsClosed = false
              AND WhatId = :appApplied.Id
              AND Subject = :nonWeekly
              AND ActivityDate = :expectedNextDue
        ];
        System.assertEquals(0, nonWeeklyCount,
            'Non-weekly subjects should not produce new tasks.');
    }

    @IsTest
    static void testAfterUpdate_emptyInputs() {
        Test.startTest();
        WeeklyTaskHandler.afterUpdate(new List<Task>(), new Map<Id, Task>());
        Test.stopTest();
        System.assert(true, 'Handler should handle empty inputs without error.');
    }
}

