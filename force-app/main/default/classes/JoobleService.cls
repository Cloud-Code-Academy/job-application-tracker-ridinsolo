public with sharing class JoobleService {
    // Data Transfer Object with fields as properties to carry data to and from LWC
    public class JobDTO {
        @AuraEnabled public String title;
        @AuraEnabled public String company;
        @AuraEnabled public String salary;
        @AuraEnabled public String link;
        @AuraEnabled public String location;
        @AuraEnabled public String snippet;
        @AuraEnabled public String type;
    }
    // Holds what is sent to Jooble from LWC inputs
    private class RequestBody {
        public String keywords; 
        public String location; 
        public Integer salary;
    }

    // Object to deserialize the response into
    private class ResponseBody {
        public Integer totalCount;
        public List<JobDTO> jobs;  // This is what the LWC renders
    }

    // Reads Jooble API key from custom metadata
    private static String getApiKey() {
        Jooble_Config__mdt cfg = [
            SELECT Api_Key__c
            FROM Jooble_Config__mdt
            LIMIT 1
        ];
        if (String.isBlank(cfg.Api_Key__c)) {
            throw new AuraHandledException('Missing Jooble API key in Custom Metadata.');
        }
        return cfg.Api_Key__c;
    }

    @AuraEnabled(cacheable=false)
    // Method that accepts job search filters (keywords, location, salary, etc.)
    // These values are placed into the RequestBody JSON and sent to Jooble
    // to retrieve matching jobs. Returns a list of JobDTO results.
    public static List<JobDTO> searchJobs (
        // from LWC input
        String keywords, 
        String location, 
        Integer salary
    ) {
        HttpRequest req = new HttpRequest(); // holder for the outbound HTTP request
        req.setMethod('POST'); // Jooble expects POST
        
        req.setHeader('Content-Type', 'application/json'); // tells Jooble request body is JSON
        req.setTimeout(20000); // avoid hanging longer than 20 seconds

        String key = getApiKey(); // Reads key from Custom Metadata
        req.setEndpoint('https://jooble.org/api/' + key); // target endpoint, requires Remote Site Setting

        // Take inputs (keywords, location, salary) and map into JSON payload Jooble expects
        RequestBody body = new RequestBody();
        body.keywords = String.isBlank(keywords) ? 'Salesforce' : keywords;
        body.location = String.isBlank(location) ? 'Remote' : location;
        if (salary != null) body.salary = salary;

        // Convert RequestBody object to JSON and attach to request
        req.setBody(JSON.serialize(body));

        // Send HTTP POST to Jooble
        Http http = new Http();
        HttpResponse res = http.send(req);

        // Handle non-200 responses so LWC shows clear message
        Integer code = res.getStatusCode();
        if (code < 200 || code >= 300) {
            throw new AuraHandledException('Jooble call failed: ' + res.getStatus() + ' - ' + res.getBody());
        }

        // Take JSON string Jooble returns and convert into ResponseBody Apex Class
        ResponseBody parsed;
        try {
            parsed = (ResponseBody) JSON.deserialize(res.getBody(), ResponseBody.class);
        } catch (Exception ex) {
            // If JSON isn't what we expected show helpful error
            throw new AuraHandledException('Could not parse Jooble response; ' + ex.getMessage());
        }

        // Return the jobs list
        return (parsed != null && parsed.jobs !=null) ? parsed.jobs : new List<JobDTO>();

    }

    @AuraEnabled
    public static List<Id> createJobApplications(List<JobDTO> selected) {
        // Guard in case nothing is chosen from LWC
        if (selected == null || selected.isEmpty()) {
            return new List<Id>();
        }
    
    // Map each selected JobDTO to a new Job Application
    List<Job_Application__c> toInsert = new List<Job_Application__c>();

    for (JobDTO j : selected) {
        Job_Application__c app = new Job_Application__c();

        // Map Jooble fields to job application fields
        app.Status__c = 'Saved';
        app.Source__c = 'Jooble';
        app.Description__c = 'Company: ' + j.company + ' | Salary: ' + j.salary + '\n' + j.snippet;
        app.Position_Title__c = j.title;
        app.Location__c = j.location;
        app.URL__c = j.link;
        app.Type__c = j.type;
        app.OwnerId = UserInfo.getUserId();

        toInsert.add(app);
    }

    insert toInsert;

    // return the new record Ids
    List<Id> ids = new List<Id>();
    for (Job_Application__c a : toInsert) ids.add(a.Id);
    return ids;
    }
}