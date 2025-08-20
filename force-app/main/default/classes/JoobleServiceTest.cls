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
            System.assert(
                ex.getMessage().startsWith('Jooble call failed'),
                'Should throw user-friendsly message on non-2xx'
            );
        }
        System.assert(threw, 'Expeccted AuraHandledException on non-2xx');
    }
}