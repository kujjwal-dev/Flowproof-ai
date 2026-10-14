/**
 * Values of the fields an investigation needs from one record, together with
 * whether each field exists and whether the running user may read it.
 * Built by the record service (user-mode SOQL + describe); consumed by the
 * condition evaluator. Field lookups are case-insensitive, like Apex field names.
 *
 * @example
 * FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot('Opportunity');
 * snapshot.putValue('StageName', 'PICKLIST', 'Closed Won');
 * snapshot.putInaccessible('Region__c');
 */
public with sharing class FlowProofRecordSnapshot {
    /** API name of the record's object. */
    public String objectApiName { get; set; }
    /** Fields keyed by lower-case API name. */
    public Map<String, FieldValue> fieldsByName { get; set; }

    /**
     * Creates an empty snapshot for one record.
     * @param objectApiName API name of the record's object
     */
    public FlowProofRecordSnapshot(String objectApiName) {
        this.objectApiName = objectApiName;
        this.fieldsByName = new Map<String, FieldValue>();
    }

    /**
     * Records a readable field and its current value (null means blank).
     * @param fieldApiName field API name
     * @param fieldType Schema.DisplayType name, e.g. PICKLIST, CURRENCY, DATE
     * @param value the field value as returned by SOQL
     */
    public void putValue(String fieldApiName, String fieldType, Object value) {
        FieldValue field = new FieldValue(fieldApiName);
        field.fieldType = fieldType;
        field.value = value;
        fieldsByName.put(fieldApiName.toLowerCase(), field);
    }

    /**
     * Records a field that exists but the running user cannot read.
     * @param fieldApiName field API name
     */
    public void putInaccessible(String fieldApiName) {
        FieldValue field = new FieldValue(fieldApiName);
        field.isAccessible = false;
        fieldsByName.put(fieldApiName.toLowerCase(), field);
    }

    /**
     * Records a field that the Flow references but the object does not have.
     * @param fieldApiName field API name
     */
    public void putMissing(String fieldApiName) {
        FieldValue field = new FieldValue(fieldApiName);
        field.exists = false;
        field.isAccessible = false;
        fieldsByName.put(fieldApiName.toLowerCase(), field);
    }

    /**
     * Looks up a field by API name.
     * @param fieldApiName field API name (any case)
     * @return the field entry, or null if the snapshot has no entry for it
     */
    public FieldValue getField(String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            return null;
        }
        return fieldsByName.get(fieldApiName.toLowerCase());
    }

    /**
     * One field's state in the snapshot.
     */
    public with sharing class FieldValue {
        /** Field API name as referenced. */
        public String fieldApiName { get; set; }
        /** False when the object has no such field. */
        public Boolean exists { get; set; }
        /** False when the running user lacks read access (value is then never populated). */
        public Boolean isAccessible { get; set; }
        /** Schema.DisplayType name; decides how the value is compared. */
        public String fieldType { get; set; }
        /** Current value; null when blank or not readable. */
        public Object value { get; set; }

        /**
         * Creates an entry for an existing, readable field.
         * @param fieldApiName field API name
         */
        public FieldValue(String fieldApiName) {
            this.fieldApiName = fieldApiName;
            this.exists = true;
            this.isAccessible = true;
        }
    }
}
