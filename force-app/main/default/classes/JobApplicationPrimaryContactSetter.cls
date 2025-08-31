public with sharing class JobApplicationPrimaryContactSetter {
   public static void setPrimaryContacts(List<Job_Application__c> jobApps) {
    // Set to collect Ids of job applications that are missing a primary contact (will be used later to query Job Application Contacts)
    Set<Id> jobAppIds = new Set<Id>();
    // Map to keep track of job application reocrds that need to be updated, allows to reference full record later
    Map<Id, Job_Application__c> jobAppMap = new Map<Id, Job_Application__c>();
    for (Job_Application__c app : jobApps) {
        if (app.Primary_Contact__c == null) {
            jobAppIds.add(app.id);
            jobAppMap.put(app.Id, app);
        }
    }
    if (jobAppIds.isEmpty()) return;

    // Create a map to group all Job Application Contacts by their Job App Id
    Map<Id, List<Job_Application_Contact__c>> jobAppToContacts = new Map<Id, List<Job_Application_Contact__c>>();
    // Query all Job Application Contacts where job application is in set JobAppIds
    for (Job_Application_Contact__c jac : [
        SELECT Id, Job_Application__c, Contact__c
        FROM Job_Application_Contact__c
        WHERE Job_Application__c IN :jobAppIds
    ]) 
    {
        // Check if job app Id is already a key in map, if not create empty list and assign to Job App Id
        if (!jobAppToContacts.containsKey(jac.Job_Application__c)) {
            jobAppToContacts.put(jac.Job_Application__c, new List<Job_Application_Contact__c>());
        }
        // Add current jac record to list for that job app
        jobAppToContacts.get(jac.Job_Application__c).add(jac);
        }
    
        Set<Id> appsNeedingFallback = new Set<Id>();

        // Loop through each job app Id that's a key in the jobAppMap to so if there are any contacts in our map, if not, add to set
        // so later can look up contacts from Company (account)
        for (Id appId : jobAppMap.keySet()) {
            List<Job_Application_Contact__c> contacts = jobAppToContacts.get(appId);
            if (contacts == null || contacts.isEmpty()) {
                appsNeedingFallback.add(appId);
            }
        }

        // Collect Account Ids from the appNeedingFallback list so can later query for related contacts so have primary contact for job app
        Set<Id> accountIds = new Set<Id>();
        for (Id appId : appsNeedingFallback) {
            Job_Application__c app = jobAppMap.get(appId);
            if (app.Company_Name__c != null) {
                accountIds.add(app.Company_Name__c);
            }
        }

        // Create map to group contacts by their account (First contact in list to be used as fallback contact for Primary Contact on job app)
        Map<Id, List<Contact>> accountToContacts = new Map<Id, List<Contact>>();
        if (!accountIds.isEmpty()) {
            for (Contact c : [
                SELECT Id, AccountId
                FROM Contact
                WHERE AccountId IN :accountIds
            ]) {
                // If the accountToContacts map doesn't already contain the account then add it and create empty list
                if (!accountToContacts.containsKey(c.AccountId)) {
                    accountToContacts.put(c.AccountId, new List<Contact>());
                }
                // Add contact to list where accountId is key
                accountToContacts.get(c.AccountId).add(c);
            }
        }

        // Create list of job applications to update in bulk
        List<Job_Application__c> updates = new List<Job_Application__c>();
        // Loop through all job apps that were passed in through trigger w/out primary contact and stored in jobAppMap
        for (Job_Application__c app : jobAppMap.values()) {
            // Check if job app has related JAC records in jobAppToContacts map and if so set first one as Primary contact
            if (jobAppToContacts.containsKey(app.Id) && !jobAppToContacts.get(app.Id).isEmpty()) {
                app.Primary_Contact__c = jobAppToContacts.get(app.Id)[0].Contact__c;
                updates.add(app);
            // If no related JACs found and job app has related company that is in accountToContacts map then set first contact as primary
            } else if (app.Company_Name__c !=null && accountToContacts.containsKey(app.Company_Name__c)) {
                List<Contact> contacts = accountToContacts.get(app.Company_Name__c);
                if (!contacts.isEmpty()) {
                    app.Primary_Contact__c = contacts[0].Id;
                    updates.add(app);
                }
            }
        }

        if(!updates.isEmpty()) {
            update updates;
        }
    }
    }