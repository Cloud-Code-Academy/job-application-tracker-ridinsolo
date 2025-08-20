@IsTest
private class JoobleServiceTest {
    // Create test only custom metadata so getApiKey works
    @testSetup
    static void setupCmt() {
        JoobleService.apiKeyOverride = 'abc123';
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
    static void testSearchJobs_success_and_cleanHTML_and_defaults() {
        // Tell Salesforce to use success mock callout
        Test.setMock(HttpCalloutMock.class, new JoobleMockOK());

        Test.startTest();
        // Call method with all null parameters
        List<JoobleService.JobDTO> jobs = JoobleService.searchJobs(null, null, null);
        Test.stopTest();

        System.assertEquals(2, jobs.size(), 'Should return 2 jobs');

        // Check that HTML was stripped
        System.assertEquals('Great role & benefits', jobs[0].snippet, 'Snippet should be cleaned of HTML tags');
        System.assertEquals('Senior Apex guru\'s', jobs[1].snippet, 'Snippet should be clearned with apostrophe');
    }

    // Mock that returns non-2xx status
    private class JoobleMockNon200 implements HTTPCalloutMock {
        public HttpResponse respond(HttpRequest reg) {
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
        System.assertEquals('Saved, admin.Status__c');
        System.assertEquals('Jooble', admin.Source__c);
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
        List<Id> none2 = JooobleService.createJobApplications(null);
        System.assertEquals(0, none2.size(), 'Null should return empty Ids');
    }
}