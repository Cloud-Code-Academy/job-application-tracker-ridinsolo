import {LightningElement,track} from 'lwc';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

import searchJobsApex from '@salesforce/apex/JoobleService.searchJobs';
import createJobApplicationsApex from '@salesforce/apex/JoobleService.createJobApplications';

// Define LWC class that extends Salesforce base functionality and is main component the js file exports
export default class JoobleJobFinder extends LightningElement {
    @track keywords = '';
    @track location = '';
    @track salary;
    @track rows = [];
    @track selectedRows = [];
    @track errorMessage = '';
    @track loading = false;

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

    // Define method that runs when user clicks search button in HTML
    async search() {
        this.loading = true;
        this.errorMessage = '';
        try {
            const result = await searchJobsApex({
                keywords: this.keywords,
                location: this.location,
                salary: this.salary
            });
            this.rows = result;
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message;
        } finally {
            this.loading = false;
        }
    }

    // Datatable columns that map to JobDTO fields from Apex
    columns = [
        {
            label: 'Title',
            fieldName: 'link',
            type: 'url',
            wrapText: true,
            typeAttributes: {label: {fieldName: 'title'}, target: '_blank'} // _blank makes link open in new tab
        },
        {label: 'Company', fieldName: 'company', type: 'text'},
        {label: 'Salary', fieldName: 'salary', type: 'text'},
        {label: 'Type', fieldName: 'type', type: 'text'},
        {label: 'Updated', fieldName: 'updated', type: 'text'},
        {label: 'Summary', fieldName: 'snippet', type: 'text', wrapText: true}
    ];    
        handleSelection(event) {
            this.selectedRows = event.detail.selectedRows || [];
        }

        // Returns true when button should be disabled
        get disableCreate() {
            return this.loading || (this.selectedRows?.length ?? 0) === 0;
        }

        // Method to create job apps from selected rows
        async createApps() {
            if(!this.selectedRows.length) return; //nothing selected, do nothing
            this.loading = true; //disable buttons and show spinner
            this.errorMessage = ''; //clear any old error

            try {
                // Send selected rows to Apex, wait til Job App records are inserted, then store record Ids in a constant variable
                const ids = await createJobApplicationsApex({selected: this.selectedRows});
                // Show pop message
                this.toast('Job Applications created', `Created ${ids.length} record(s)`, 'success');
                this.selectedRows = []; // clear selection after insert
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


    
