public with sharing class WeeklyTaskHandler {

     public static void afterUpdate(List<Task> newList, Map<Id, Task> oldMap) {
    // Instantiate list of tasks that will hold weekly tasks that went from open to closed, are related to Job Application, and are weekly
    List<Task> justClosedWeekly = new List<Task>();
    // Loop through tasks, get the previous version of task before update so can verify later in code if task went from open to closed
    for (Task t : newList) {
        Task oldT = oldMap.get(t.Id);

        // Boolean variable that is true when task transitions from open to closed
        Boolean becameClosed = (oldT != null && oldT.IsClosed == false && t.IsClosed == true);
        // Boolean variable that is true when updated task's subject starts with weekly tag that is set in JobApplicationTaskCreation class
        Boolean isWeekly = (t.Subject != null && t.Subject.startsWith(JobApplicationTaskCreation.WEEKLY_TAG));
        // Boolean variable that is true when the WhatId field is NOT null and is type Job Application
        Boolean isJobApp = (t.WhatId != null && t.WhatId.getSObjectType() == Job_Application__c.SObjectType);

        if (becameClosed && isWeekly && isJobApp) {
            justClosedWeekly.add(t);
        }
    }
    // Get parent Job applications
    // For all tasks that met criteria (Went from open to closed, related to Job App, weekly), add Job Application (WhatId) record Ids to a set. 
    Set<Id> whatIds = new Set<Id>();
    for (Task t : justClosedWeekly) {
        whatIds.add(t.WhatId);
    }
    // Create map where key is Job Application record Id and value is the related job application record
    Map<Id, Job_Application__c> appsById = new Map<Id, Job_Application__c>([
        SELECT Id, Status__c
        FROM Job_Application__c
        WHERE Id IN :whatIds
    ]);
    // Defensive coding just in case 
    if (appsById.isEmpty()) return;

    // Keep just tasks whose parent application status is still "Applied"
    // Create list of tasks that are candidates for creating a copy of weekly task
    List<Task> candidates = new List<Task>();
    // Loop through the tasks in list justClosedWeekly and see if the related Job application record is a status of "Applied".
    // If application is status "Applied" add task to list of tasks that are candidates for being copied. 
    for (Task t : justClosedWeekly) {
        Job_Application__c app = appsById.get(t.WhatId);
        if (app != null && app.Status__c == 'Applied') {
            candidates.add(t);
        }
    }
    if (candidates.isEmpty()) return;

    // Create sets to check for duplicates
    Set<Id> candOwnerIds = new Set<Id>();
    Set<String> candSubjects = new Set<String>();
    Set<Id> candWhatIds = new Set<Id>();
    for (Task t : candidates) {
        candOwnerIds.add(t.OwnerId);
        candSubjects.add(t.Subject);
        candWhatIds.add(t.WhatId);
    }

    // Find matching open tasks with same WhatId + OwnerId + Subject
    Set<String> openKeys = new Set<String>();
    for (Task tOpen : [
        SELECT Id, WhatId, OwnerId, Subject, IsClosed
        FROM Task
        WHERE IsClosed = false
            AND WhatId IN :candWhatIds
            AND OwnerId IN :candOwnerIds
            AND Subject IN :candSubjects
    ]) {
        String k = String.valueOf(tOpen.WhatId) + '|' + String.valueOf(tOpen.OwnerId) + '|' + tOpen.Subject;
        openKeys.add(k);
    }

    // Create the next weekly tasks due 7 days from today
    Date nextDue = Date.today().addDays(7);
    List<Task> toInsert = new List<Task>();
    for (Task closedWeekly : candidates) {
        String k = String.valueOf(closedWeekly.WhatId) + '|' + String.valueOf(closedWeekly.OwnerId) + '|' + closedWeekly.Subject;
        if (openKeys.contains(k)) continue; // A matching open task already exists

        Task nextT = new Task();
        nextT.WhatId = closedWeekly.WhatId;
        nextT.OwnerId = closedWeekly.OwnerId;
        nextT.Subject = closedWeekly.Subject;
        nextT.Priority = closedWeekly.Priority;
        nextT.ActivityDate = nextDue;
        toInsert.add(nextT);
    }

    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
}
}