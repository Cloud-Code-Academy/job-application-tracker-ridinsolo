// JavaScript for Jooble Job Finder LWC
// Purpose: Let a user search Jooble jobs, page through results, select rows across pages, creat Job app records in Salesforce

import {LightningElement,track} from 'lwc';
// Toasts: import the standard Lightning event for popup messages in the UI.
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

import searchJobsApex from '@salesforce/apex/JoobleService.searchJobs';
import createJobApplicationsApex from '@salesforce/apex/JoobleService.createJobApplications';

// define a class, export it as the default so the framework can find it, 
// and extend LightningElement so Salesforce knows to treat it as a Lightning Web Component
export default class JoobleJobFinder extends LightningElement {
    // inputs
    @track keywords = '';
    @track location = '';
    @track salary;

    // results + ui state
    @track rows = []; // current page rows
    @track errorMessage = '';
    @track loading = false;

    // paging
    @track page = 1; // page to start on
    @track pageSize = 25;
    // Total number of jobs returned. Used to calculate how many pages exist and to disable next button on last page
    @track totalCount = 0;

    // selection (to persists across pages)
    selectedCache = new Map(); // Map to store ALL user selected rows across pages. Key = string generated with makeKey(row), row=full row
    @track selectedRowKeys = []; // List of keys just for rows on CURRENT page. Lightning-datatable use for selected-rows property to know which checkboxes to who as checked

    // Datatable columns (referenced in HTML template) that map to JobDTO fields from Apex
    columns = [
        {
            label: 'Title', // column header text
            fieldName: 'link', // the field in row data to use
            type: 'url', // render as a hyperlink
            wrapText: true, // allow wrapping if text is long
            typeAttributes: {
                label: {fieldName: 'title'}, // link text = row.title
                target: '_blank' // _blank makes link open in new tab
            }
        },
        {label: 'Company', fieldName: 'company', type: 'text'},
        {label: 'Salary', fieldName: 'salary', type: 'text'},
        {label: 'Type', fieldName: 'type', type: 'text'},
        {label: 'Location', fieldName: 'location', type: 'text'},
        {label: 'Summary', fieldName: 'snippet', type: 'text', wrapText: true}
    ]; 

    // Wire inputs and buttons in HTML. Function acts as listener that keeps JS in sync with what's typed in UI.
    handleInput(event) {
        const field = event.target.label;
        if (field === 'Keywords') {
            this.keywords = event.target.value;
        } else if (field === 'Location') {
            this.location = event.target.value;
        } else if (field === 'Minimum Salary') {
            this.salary = event.target.value ? parseInt(event.target.value, 10) : null; // set typed value to # if value entered, otherwise set to null
        }
    }

    // Search button resets page and clears selection, then fetches
    async search() {
        if (this.page !== 1) this.page = 1;
        this.selectedCache.clear(); // clear old selections on new search
        await this.fetchPage(); // call the shared fetcher but wait until results are in
    }

    // Need to make a unique key per job so row info saved when moving btwn pages
    makeKey(r) {
        // Normalize link if present: remove ?query and #hash, strip trailing slash, lowercase
        const rawLink = (r.link || '').toString().trim();
        const linkBase = rawLink
            ? rawLink.split(/[?#]/)[0].replace(/\/+$/, '').toLowerCase()
            : '';

        if (linkBase) return `k:${linkBase}`;

        // Fallback: combo of other fields
        const parts = [r.title, r.company, r.location, r.type, r.salary]
            .map(v => (v || '').toString().trim().toLowerCase());
        return `k:${parts.join('|')}`;
    }

    // Load the current page of results from Apex (which calls Jooble)
    async fetchPage() {
        this.loading = true; // show spinner
        this.errorMessage = ''; // clear previous errors
        try {
            // Call apex with current search and paging inputs. Page is sent as string cause that is Apex param. 
            const result = await searchJobsApex({
                keywords: this.keywords,
                location: this.location,
                salary: this.salary,
                page: String(this.page),
                resultOnPage: this.pageSize // tells Apex how many rows to return per page (set to 25)
            });
            const rawRows = result?.jobs || []; // if Apex returned jobs use them, otherwise fallback to empty array
            this.rows = rawRows.map(r => ({ // take each job object from Apex and build new array of rows
                ...r,                       // copy the fields 
                _key: this.makeKey(r)       // add stable key to each job object
            }));
            
            this.totalCount = result?.totalCount || 0;
            this.syncSelectedRowKeys(); // keep previously selected rows checked
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message; // If Apex includes detailed error message use that, otherwise use generic message
        } finally {
            this.loading = false;
        }
    }

    // Paging calls fetchPage()
    async nextPage() {
        if (this.disableNext) return; 
        this.page += 1;
        await this.fetchPage();
    }
    async prevPage() {
        if (this.disablePrev) return;
        this.page = Math.max(1, this.page - 1); // decrease the page # by 1 but never below 1
        await this.fetchPage();
    }
   
        handleSelection(event) {
            const selectedOnThisPage = new Set((event.detail.selectedRows || []).map(r => r._key)); // key-field
            for (const row of this.rows) {
                const key = row._key;
                if (selectedOnThisPage.has(key)) {
                    this.selectedCache.set(key, row); // add/update selection
                } else {
                    this.selectedCache.delete(key); // unselect if unchecked
                }
            }
            this.syncSelectedRowKeys();
        }

        syncSelectedRowKeys() {
            const currentKeys = new Set((this.rows || []).map(r => r._key));
            // Show checkboxes only for rows that exist on this page
            this.selectedRowKeys = Array.from(this.selectedCache.keys()).filter(k => currentKeys.has(k));
        }

        // Returns true when button should be disabled
        get disableCreate() {
            return this.loading || this.selectedCache.size === 0; // Create button disabled if loading or no selections
        }
        // Take total # of jobs from Apex (this.totalCount) and divide by how many rows show per page (this.pageSize)
        get totalPages() {
            return Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize)); // Math.ceil used to round up, Math.max ensures always 1
        }
        get disablePrev() {
            return this.loading || this.page <= 1; // prev button disabled during spinning if at first page or if loading is true
        }
        get disableNext() {
            return this.loading || this.page >= this.totalPages; // next button disabled during loading and if at last page
        }

        // Method to assemble data from selected rows across pages to send to Apex to create job apps
        async createApps() {
            // Build payload from ALL selected rows across pages, field match field defined in JobDTO in Apex class
            const payload = Array.from(this.selectedCache.values()).map(r => ({
                    title:   r.title,
                    company: r.company,
                    salary:  r.salary,
                    link:    r.link,
                    location:r.location,
                    snippet: r.snippet,
                    type:    r.type,
            }));
            if (!payload.length) return; //nothing selected, do nothing

            this.loading = true; //disable buttons and show spinner
            this.errorMessage = ''; //clear any old error

            try {
                // Send selected rows to Apex, wait til Job App records are inserted, then store record Ids in a constant variable
                const ids = await createJobApplicationsApex({selected: payload});
                // Show pop message
                this.toast('Job Applications created', `Created ${ids.length} record(s)`, 'success');
                this.selectedCache.clear(); // clear selection after insert
                this.syncSelectedRowKeys(); // tells datatable no checkboxes are selected
            } catch (e) {
                // Set this.errorMessage to most detailed error message available otherwise show "Insert Failed" in pop up error message
                this.errorMessage = e?.body?.message || e?.message || 'Insert failed';
                this.toast('Insert failed', this.errorMessage, 'error');
            } finally {
                this.loading = false; // re-enable UI
            }
        }

        toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({title, message, variant}));
    }
}



    
