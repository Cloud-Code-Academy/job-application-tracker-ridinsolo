public class JobApplicationTaskCreation {
    // Inner class that acts as a container for tasks to be created
    public class TaskContainer {
        public String subject;
        public Integer dueInDays;
        public String priority;
        // Class constructor with parameters
        public TaskContainer(String subject, Integer dueInDays, String priority) {
            this.subject = subject;
            this.dueInDays = dueInDays;
            this.priority = priority;
        }
    }

    // Tag used to identify weekly tasks
    public static final String WEEKLY_TAG = '[Weekly]';

    // Create map to hold job application status as key and list of tasks for each status as value. 
    private static Map<String, List<TaskContainer>> tasksByStatus = new Map<String, List<TaskContainer>>{
        'Saved' => new List<TaskContainer>{
            new TaskContainer('Check if the job description aligns with your interests and values', 1, 'Normal'),
            new TaskContainer('Review the highlighted skills to see if the role is a good fit' , 1, 'Normal'),
            new TaskContainer('Research the company or role and mark your excitement level', 1, 'Normal')
        },
        'Applying' => new List<TaskContainer> {
            new TaskContainer('Find and research someone who works at the company and add them as a contact', 5, 'Normal'),
            new TaskContainer('Set up an informational interview to learn more about the role/company', 5, 'Normal'),
            new TaskContainer('Identify potential referrals to help get your application on the top of the pile', 5, 'Normal'),
            new TaskContainer('Customize your work achievements using the job description keywords', 5, 'Normal'),
            new TaskContainer('Submit your application on the company website if possible', 5, 'Normal')
        },
        'Applied' => new List<TaskContainer>{
            new TaskContainer('Reach out to the hiring manager or recruiter', 1, 'High'),
            new TaskContainer(WEEKLY_TAG + ' Follow up on your application via email weekly', 7, 'High'),
            new TaskContainer('Continue identifying and saving similar job opportunities', 5, 'Low'),
            new TaskContainer(WEEKLY_TAG + ' Set up weekly networking calls to explore similar companies/roles', 7, 'Low')
        },
        'Interviewing' => new List<TaskContainer>{
            new TaskContainer('Prepare your blurb or “tell me about yourself” response', 2, 'High'),
            new TaskContainer('Practice answering behavioral interview questions', 2, 'High'),
            new TaskContainer('Research the company and your interviewers', 2, 'High'),
            new TaskContainer('Set up your virtual interview space and test your tech', 1, 'High'),
            new TaskContainer('Send thank you emails within 24 hours', 1, 'High')
        },
        'Negotiating' => new List<TaskContainer>{
            new TaskContainer('Research your market value and know your numbers', 2, 'Normal'),
            new TaskContainer('Prepare your negotiation scripts', 2, 'Normal'),
            new TaskContainer('Evaluate your offer and decline or accept', 2, 'Normal')
        },
        'Accepted' => new List<TaskContainer>{
            new TaskContainer('Plan your resignation if applicable', 3, 'Normal'),
            new TaskContainer('Take some time to relax and recharge', 7, 'Low'),
            new TaskContainer('Prepare for your first day of onboarding', 2, 'Normal')
        },
        'Closed' => new List<TaskContainer>{
            new TaskContainer('Send a follow-up email thanking the interviewer and asking for feedback', 1, 'High'),
            new TaskContainer('Review your notes and reflect on areas of improvement', 2, 'Normal')
        }
    };

    // Method called by trigger handler to create tasks
    public static void createTasksForApplications(List<Job_Application__c> newList, Map<Id, Job_Application__c> oldMap) {
        // Null checks
        if (newList == null || newList.isEmpty()) return;

        // Decide which applications should get tasks
        List<Job_Application__c> toProcess = new List<Job_Application__c>();
        // Loop through all the job applications in the new list of job applications that came from the trigger.new
        for (Job_Application__c ja : newList) {
            // Check if status is null then statusNow is null, otherwise trim status of whitespace to be safe
            String statusNow = (ja.Status__c == null) ? null : ja.Status__c.trim();
            // If statusNow is blank or taskByStatus map doesn't contain the same status found in statusNow jump to next loop iteration
            if (String.isBlank(statusNow) || !tasksByStatus.containsKey(statusNow)) continue;

            // On insert, always proces; on update, only if status actually changed
            if (oldMap == null) {
                toProcess.add(ja);
            } else {
                Job_Application__c oldJa = oldMap.get(ja.Id);
                String statusOld = (oldJa == null || oldJa.Status__c == null) ? null : oldJa.Status__c.trim();
                if (statusOld != statusNow) {
                    toProcess.add(ja);
                } 
            }
        }
        // Empty list, end
        if(toProcess.isEmpty()) return;

        // WhatIds and subjects to prevent duplicates
        Set<Id> whatIds = new Set<Id>();
        Set<String> subjectsNeeded = new Set<String>();
        // Map from each job app Id to it's planned list of TaskContainer items
        Map<Id, List<TaskContainer>> planPerApp = new Map<Id, List<TaskContainer>>();

        // Loop through each of the job applications in the toProcess list
        for (Job_Application__c ja : toProcess) {
            // Put the job application Id in the whatIds set
            whatIds.add(ja.Id);
            // Get task plan for the job apps current status
            List<TaskContainer> plan = tasksByStatus.get(ja.Status__c.trim());
            // Save plan for the specific job application in map
            planPerApp.put(ja.Id, plan);
            // Loop over plan, add subject to subjects needed
            for (TaskContainer tc : plan) {
                subjectsNeeded.add(tc.subject);
            }
        }

        // Create a string set that acts like a key, made by concatenating WhatId, OwnerId, and Subject
        Set<String> existingTaskKeys = new Set<String>();
        if (!whatIds.isEmpty() && !subjectsNeeded.isEmpty()) {
            for (Task t : [
                SELECT Id, WhatId, Subject, OwnerId, Status
                FROM Task
                WHERE WhatId IN :whatIds
                AND Subject IN :subjectsNeeded
                AND Status != 'Completed'
            ]) {
                existingTaskKeys.add(
                    String.valueOf(t.WhatId) + '|' +
                    String.valueOf(t.OwnerId) + '|' +
                    (t.Subject == null ? '' : t.Subject.trim().toLowerCase())
                );
            }
        }

        //Build new tasks, skipping any whose task key already exists
        List<Task> toInsert = new List<Task>();
        Date today = Date.today();

        // For each job app get its pre-defined plan of tasks 
        for (Job_Application__c ja : toProcess) {
            List<TaskContainer> plan = planPerApp.get(ja.Id);
            if (plan == null) continue;

            // Loop through planned tasks for job application and build task key 
            for (TaskContainer tc : plan) {
                Id plannedOwnerId = ja.OwnerId;
                String plannedTaskKey =
                    String.valueOf(ja.Id) + '|' +
                    String.valueOf(plannedOwnerId) + '|' +
                    ((tc.subject == null) ? '' : tc.subject.trim().toLowerCase());

                // Skip building task if it's a duplicate
                if (existingTaskKeys.contains(plannedTaskKey)) continue;

                Task nt = new Task();
                nt.Subject = tc.subject;
                nt.Priority = tc.priority;
                nt.Status = 'Saved';
                nt.ActivityDate = today.addDays(tc.dueInDays == null ? 0 : tc.dueInDays);
                nt.WhatId = ja.Id;
                nt.OwnerId = ja.OwnerId;

                toInsert.add(nt);
        }
    }

    // Insert new tasks in bulk
    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
}
}