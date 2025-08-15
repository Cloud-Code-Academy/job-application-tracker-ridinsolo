public without sharing class JobApplicationCloseStaleBatch implements Database.Batchable<SObject>, Schedulable {
    // Query all qualifying records
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Follow_Up_Date__c, Notes__c
            FROM Job_Application__c
            WHERE Status__c NOT IN ('Closed', 'Accepted')
                AND Follow_Up_Date__c != null
                AND Follow_Up_Date__c <= :Date.today().addDays(-30)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if(scope.isEmpty()) return;

        List<Job_Application__c> toUpdate = new List<Job_Application__c>();

        String todayStamp = DateTime.now().format('yyyy-MM-dd HH:mm');

        for (SObject sob : scope) {
            Job_Application__c app = (Job_Application__c)sob; //cast SObject to job app object
            app.Status__c = 'Closed';
            String existing = app.Notes__c;
            // Update notes with time closed and closed automatically
            String prefix = String.isBlank(existing) ? '' : existing.trim() + '\n';
            app.Notes__c = prefix + '[Auto-Closure ' + todayStamp + '] Closed by scheduled process due to stale follow-up date.';
            
            toUpdate.add(app);
        }

        // Continue if error so one bad record doesn't stop batch
        Database.update(toUpdate, /* allOrNone */ false);
    }

    public void finish(Database.BatchableContext bc) {}
    }
