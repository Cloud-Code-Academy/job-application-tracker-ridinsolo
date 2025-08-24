import {LightningElement,track} from 'lwc';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

import searchJobsApex from '@salesforce/apex/JoobleService.searchJobs';
import createJobApplicationsApex from '@salesforce/apex/JoobleService.createJobApplications';

// Define LWC class that extends Salesforce base functionality and is main component the js file exports
export default class JoobleJobFinder extends LightningElement {
    // inputs
    @track keywords = '';
    @track location = '';
    @track salary;

    // results + ui state
    @track rows = [];
    @track errorMessage = '';
    @track loading = false;

    // paging
    @track page = 1;
    @track pageSize = 25;
    @track totalCount = 0;

    // selection (to persists across pages)
    selectedCache = new Map(); //key -> row
    @track selectedRowKeys = []; // used by datatable selected-rows

    // Datatable columns that map to JobDTO fields from Apex
    columns = [
        {
            label: 'Title',
            fieldName: 'link',
            type: 'url',
            wrapText: true,
            // _blank makes link open in new tab
            typeAttributes: {label: {fieldName: 'title'}, target: '_blank'} 
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
            this.salary = event.target.value ? parseInt(event.target.value, 10) : null;
        }
    }

    // Search button resets page and clears selection, then fetches
    async search() {
        if (this.page !== 1) this.page = 1;
        this.selectedCache.clear(); // clear old selections on new search
        await this.fetchPage(); // call the shared fetcher
    }

    makeKey(r) {
        // Normalize link if present: remove ?query and #hash, strip trailing slash, lowercase
        const rawLink = (r.link || '').toString().trim();
        const linkBase = rawLink
            ? rawLink.split(/[?#]/)[0].replace(/\/+$/, '').toLowerCase()
            : '';

        if (linkBase) return `k:${linkBase}`;

        // Fallback: stable fingerprint from other fields
        const parts = [r.title, r.company, r.location, r.type, r.salary]
            .map(v => (v || '').toString().trim().toLowerCase());
        return `k:${parts.join('|')}`;
    }


    async fetchPage() {
        this.loading = true;
        this.errorMessage = '';
        try {
            const result = await searchJobsApex({
                keywords: this.keywords,
                location: this.location,
                salary: this.salary,
                page: String(this.page),
                resultOnPage: this.pageSize
            });
            // Apex should return {totalCount, jobs}
            // Build stable keys for this page (don’t rely on link being unique or present)
            const rawRows = result?.jobs || [];
            this.rows = rawRows.map(r => ({
                ...r,
                _key: this.makeKey(r)
            }));
            
            this.totalCount = result?.totalCount || 0;
            this.syncSelectedRowKeys(); // keep previously selected rows checked
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message;
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
        this.page = Math.max(1, this.page - 1);
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
            return this.loading || this.selectedCache.size === 0;
        }
        // Compute pages and wire up Next/Prev buttons
        get totalPages() {
            return Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));
        }
        get disablePrev() {
            return this.loading || this.page <= 1;
        }
        get disableNext() {
            return this.loading || this.page >= this.totalPages;
        }

        // Method to create job apps from selected rows across pages
        async createApps() {
            // Build payload from ALL selected rows across pages
            const payload = Array.from(this.selectedCache.values()).map(r => ({
                    title:   r.title,
                    company: r.company,
                    salary:  r.salary,
                    link:    r.link,
                    location:r.location,
                    snippet: r.snippet,
                    type:    r.type,
                    updated: r.updated
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
                this.syncSelectedRowKeys();
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



    
