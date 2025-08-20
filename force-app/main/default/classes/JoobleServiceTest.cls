@IsTest
private class JoobleServiceTest {
    // Create test only custom metadata so getApiKey works
    @testSetup
    static void setupCmt() {
        JoobleService.apiKeyOverride = 'abc123';
    }

    private class JoobleMockBadJson implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse r = new HttpResponse();
        r.setStatusCode(200);
        r.setStatus('200 OK');
        // Intentionally wrong shape to trigger the catch block
        r.setBody('{"jobs":"not-a-list"}');
        return r;
    }
}
@IsTest
static void testSearchJobs_badJson_throwsHandledException() {
    Test.setMock(HttpCalloutMock.class, new JoobleMockBadJson());

    Boolean threw = false;
    try {
        JoobleService.searchJobs('x', 'y', 123);
    } catch (AuraHandledException ex) {
        threw = true; // message may be masked as "Script-thrown exception"
    }
    System.assert(threw, 'Expected AuraHandledException on bad JSON');
}


    // Mocks successful Jooble API call so searchJobs method runs w/out real HTTP request
    private class JoobleMockOK implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            // Validate request method and endpoint
            System.assertEquals('POST', req.getMethod(), 'Expected POST');
            String ep = req.getEndpoint();
            System.assert(
                ep.startsWith('https://jooble.org/api/') || ep.startsWith('callout:'),
                'Expected Jooble API base URL or Named Credential. Got: ' + ep
            );

            // Verify body defaults when nulls are used in searchJobs
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            System.assertEquals('Salesforce', (String)sent.get('keywords'), 'Default keywords should be Salesforce');
            System.assertEquals('Remote', (String)sent.get('location'), 'Default location should be Remote');
            System.assertEquals(false, sent.containsKey('salary'), 'Salary should be omitted when null');

            // Build a 200 response with two jobs including HTML to exercise cleanHTML
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('200 OK');
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"totalCount":2,"jobs":[' +
                '{"title":"Admin","company":"Acme","salary":"$100k","link":"https://example.com/1","location":"Remote","snippet":"<b>Great</b> role &amp; benefits","type":"Full-time"},' +
                '{"title":"Dev","company":"Beta","salary":"$120k","link":"https://example.com/2","location":"Boise, ID","snippet":"Senior &lt;i&gt;Apex&lt;/i&gt; guru&#39;s","type":"Contract"}' +
            ']}'
        );
        return res;
        }
    }

    @IsTest
    static void testSearchJobs_success_and_cleanHtml_and_defaults() {
        // Tell Salesforce to use success mock callout
        Test.setMock(HttpCalloutMock.class, new JoobleMockOK());

        Test.startTest();
        // Call method with all null parameters
        List<JoobleService.JobDTO> jobs = JoobleService.searchJobs(null, null, null);
        Test.stopTest();

        System.assertEquals(2, jobs.size(), 'Should return 2 jobs');

        // Check that HTML was stripped
        System.assertEquals('Great role & benefits', jobs[0].snippet, 'Snippet should be cleaned of HTML tags');
        System.assertEquals('Senior Apex guru\'s', jobs[1].snippet, 'Snippet should be cleaned with apostrophe');
    }

    // Mock that returns non-2xx status
    private class JoobleMockNon200 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(500);
            r.setStatus('500 Server Error');
            r.setBody('oops');
            return r;
        }
    }

    @IsTest
    static void testSearchJobs_non200_throwsHandledException() {
        Test.setMock(HttpCalloutMock.class, new JoobleMockNon200());

        Boolean threw = false;
        try {
            JoobleService.searchJobs('k', 'l', 100);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException on non-2xx');
    }

    @IsTest
    static void testCreateJobApplications_inserts_and_maps_fields() {
        // Use success mock to get two JobDTOs
        Test.setMock(HttpCalloutMock.class, new JoobleMockOK());

        Test.startTest();
        List<JoobleService.JobDTO> jobs = JoobleService.searchJobs(null, null, null);
        List<Id> newIds = JoobleService.createJobApplications(jobs);
        Test.stopTest();

        System.assertEquals(2, newIds.size(), 'Should return 2 new Ids');

        // Verify mappings on the inserted records
        List<Job_Application__c> apps = [
            SELECT Id, Status__c, Source__c, Description__c,
                    Position_Title__c, Location__c, URL__c, Type__c, OwnerId
            FROM Job_Application__c
            WHERE Id IN :newIds
            ORDER BY Position_Title__c
        ];
        System.assertEquals(2, apps.size(), 'Should insert 2 Job Applications');

        // Admin job
        Job_Application__c admin = apps[0];
        System.assertEquals('Saved', admin.Status__c, 'Status should be Saved');
        System.assertEquals('Jooble', admin.Source__c, 'Source__c should be Jooble');
        System.assert(admin.Description__c.contains('Company: Acme'), 'Description should include company');
        System.assert(admin.Description__c.contains('Salary: $100k'), 'Description should include salary');
        System.assert(admin.Description__c.contains('Great role & benefits'), 'Description should include cleaned snippet');
        System.assertEquals('Admin', admin.Position_Title__c, 'Job title should map from JobDTO.title');
        System.assertEquals('Remote', admin.Location__c, 'Location should map from JobDTO.location');
        System.assertEquals('https://example.com/1', admin.URL__c, 'URL should map from JobDTO.link');
        System.assertEquals('Full-time', admin.Type__c, 'Type should map from JobDTO.type');
        System.assertEquals(UserInfo.getUserId(), admin.OwnerId, 'OwnerId should map to current user');

        // Dev job
        Job_Application__c dev = apps[1];
        System.assertEquals('Dev', dev.Position_Title__c, 'Job title should map from JobDTO.title');
        System.assertEquals('Boise, ID', dev.Location__c, 'Location should map from JobDTO.location');
        System.assertEquals('https://example.com/2', dev.URL__c, 'URL should map from JobDTO.link');
        System.assertEquals('Contract', dev.Type__c, 'Type should map from JobDTO.type');
        System.assert(dev.Description__c.contains('Senior Apex guru\'s'),
            'Description should include cleaned snippet with apostrophe');        
        }

    @IsTest
    static void testCreateJobApplications_handles_empty_input() {
        // Empty list
        List<Id> none1 = JoobleService.createJobApplications(new List<JoobleService.JobDTO>());
        System.assertEquals(0, none1.size(), 'Empty list should return empty Ids');

        // Null
        List<Id> none2 = JoobleService.createJobApplications(null);
        System.assertEquals(0, none2.size(), 'Null should return empty Ids');
    }

    @IsTest 
    static void testCreateJobApplications_bulk_inserts_all() {
        // Build a larte list of JobDTOs without doing callouts
        Integer n = 201;
        List<JoobleService.JobDTO> jobs = new List<JoobleService.JobDTO>();
        for (Integer i = 1; i <= n; i++) {
            JoobleService.JobDTO j = new JoobleService.JobDTO();
            j.title = 'Role ' + i;
            j.company = 'Company ' + i;
            j.salary = '$' + (50000 + i);
            j.link = 'https://example.com/job/' + i;
            j.location = (Math.mod(i, 2) == 0) ? 'Remote' : 'Boise, ID';
            j.snippet = 'Summary ' + i; // no HTML needed here; createJobApplications doesn’t clean
            j.type = (Math.mod(i, 3) == 0) ? 'Contract' : 'Full-time';
            jobs.add(j);            
        }

        Test.startTest();
        List<Id> newIds = JoobleService.createJobApplications(jobs);
        Test.stopTest();

        // All job applications should be inserted
        System.assertEquals(n, newIds.size(), 'Should insert all Job Applications');

        // Spot-check a few records for correct mapping
        List<Job_Application__c> sample = [
            SELECT Position_Title__c, Source__c, Status__c, Description__c,
                Location__c, URL__c, Type__c, OwnerId
            FROM Job_Application__c
            WHERE Id IN :newIds
            ORDER BY Position_Title__c
            LIMIT 3
        ];           
        System.assertEquals(true, sample.size() > 0, 'Should retrieve sample rows');
        for (Job_Application__c a : sample) {
            System.assertEquals('Saved', a.Status__c, 'Status should equal saved');
            System.assertEquals('Jooble', a.Source__c, 'Source should be Jooble');
            System.assert(a.Description__c.startsWith('Company:'), 'Description should start with Company:');
            System.assertEquals(UserInfo.getUserId(), a.OwnerId, 'OwnerId should be current user');
            System.assertNotEquals(null, a.URL__c, 'URL should be set');
            System.assertNotEquals(null, a.Type__c, 'Type should be set');
        }       
    }
    // Mock that verifies non-null inputs and Content-Type header
private class JoobleMockChecksInputs implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        // Header check
        System.assertEquals('application/json', req.getHeader('Content-Type'), 'Content-Type header should be application/json');

        // Body checks: keywords/location should reflect inputs, salary should be present
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
        System.assertEquals('Admin', (String)sent.get('keywords'), 'keywords should use provided value');
        System.assertEquals('Boise', (String)sent.get('location'), 'location should use provided value');
        System.assertEquals(true, sent.containsKey('salary'), 'salary should be included when provided');
        System.assertEquals(90000, (Integer)sent.get('salary'), 'salary should match provided value');

        // Return a simple valid response
        HttpResponse r = new HttpResponse();
        r.setStatusCode(200);
        r.setStatus('200 OK');
        r.setBody('{"totalCount":1,"jobs":[{"title":"Admin","company":"Acme","salary":"$90k","link":"https://ex/1","location":"Boise","snippet":"Good role","type":"Full-time"}]}');
        return r;
    }
}

@IsTest
static void testSearchJobs_uses_provided_inputs_in_request_body() {
    Test.setMock(HttpCalloutMock.class, new JoobleMockChecksInputs());

    List<JoobleService.JobDTO> jobs = JoobleService.searchJobs('Admin', 'Boise', 90000);

    System.assertEquals(1, jobs.size(), 'searchJobs should return 1 job from mock response');
    System.assertEquals('Admin', jobs[0].title, 'Title should deserialize from response');
}
// Mock that returns 200 OK with jobs = null
private class JoobleMockNoJobs implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
        HttpResponse r = new HttpResponse();
        r.setStatusCode(200);
        r.setStatus('200 OK');
        r.setBody('{"totalCount":0,"jobs":null}');
        return r;
    }
}

@IsTest
static void testSearchJobs_returns_empty_list_when_no_jobs() {
    Test.setMock(HttpCalloutMock.class, new JoobleMockNoJobs());

    List<JoobleService.JobDTO> jobs = JoobleService.searchJobs(null, null, null);

    System.assertEquals(0, jobs.size(), 'Should return empty list when response has no jobs');
}

}