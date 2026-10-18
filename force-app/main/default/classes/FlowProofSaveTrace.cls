/**
 * What really happened when a record was saved, read from the debug log of that save: which
 * record-triggered Flows ran (and what they did), which active ones did not start, and which
 * validation rules failed. Confirmed evidence for that one save; not saved by FlowProof.
 */
public with sharing class FlowProofSaveTrace {
    /** True when a debug log of a save of the record was found. */
    @AuraEnabled
    public Boolean logFound { get; set; }
    /** RECORD_ID (a Flow ran for the record) or SAVE_TIME (matched by the record's last-modified time). */
    @AuraEnabled
    public String matchedBy { get; set; }
    /** When the logged save started. */
    @AuraEnabled
    public Datetime savedAt { get; set; }
    /** Where the save came from, e.g. Lightning page or API. */
    @AuraEnabled
    public String source { get; set; }
    /** Flows that ran for the record, in the order they ran. */
    @AuraEnabled
    public List<FlowRun> ran { get; set; }
    /** Labels of active record-triggered Flows on the object that did not start on this save. */
    @AuraEnabled
    public List<String> notStarted { get; set; }
    /** Validation rules that failed, and their messages. */
    @AuraEnabled
    public List<String> validationFailures { get; set; }
    /** Explanation when no matching save was found, or other notes. */
    @AuraEnabled
    public String message { get; set; }
    /** True when FlowProof switched debug logging off again. */
    @AuraEnabled
    public Boolean loggingStopped { get; set; }

    /**
     * Creates an empty result.
     */
    public FlowProofSaveTrace() {
        this.logFound = false;
        this.ran = new List<FlowRun>();
        this.notStarted = new List<String>();
        this.validationFailures = new List<String>();
        this.loggingStopped = false;
    }

    /** One Flow that ran during the save. */
    public with sharing class FlowRun {
        /** Flow label. */
        @AuraEnabled
        public String label { get; set; }
        /** FINISHED, FAILED or STARTED (started but no finish was logged). */
        @AuraEnabled
        public String statusCode { get; set; }
        /** Elements that ran, e.g. "Create Task" (Create Records). */
        @AuraEnabled
        public List<String> elements { get; set; }
        /** Decision outcomes that were taken. */
        @AuraEnabled
        public List<String> outcomes { get; set; }
        /** Errors from the log. */
        @AuraEnabled
        public List<String> errors { get; set; }

        /**
         * @param interview the parsed interview
         */
        public FlowRun(FlowProofDebugLogParser.Interview interview) {
            this.label = interview.label;
            this.elements = interview.elements;
            this.outcomes = interview.outcomes;
            this.errors = interview.errors;
            if (!interview.errors.isEmpty()) {
                this.statusCode = 'FAILED';
            } else {
                this.statusCode = interview.finished ? 'FINISHED' : 'STARTED';
            }
        }
    }
}
