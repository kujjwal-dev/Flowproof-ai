/**
 * Reads the current values of the fields an investigation needs from one record, with the
 * running user's permissions. Fields the user cannot read are recorded as inaccessible and are
 * never queried; fields the object lacks are recorded as missing. Relationship paths
 * (for example Account.Industry) are skipped: the evaluator reports them as unsupported.
 *
 * SOQL safety: the object and field names come from Schema describe results, never from the
 * caller's strings, and the record Id is a bind variable.
 *
 * @example
 * FlowProofRecordSnapshot snapshot = new FlowProofRecordService()
 *     .getSnapshot('Opportunity', opportunityId, new Set<String>{ 'StageName', 'Amount' });
 */
public with sharing class FlowProofRecordService {
    /**
     * Builds a snapshot of the requested fields of one record.
     * @param objectApiName API name of the record's object
     * @param recordId the record
     * @param fieldApiNames fields to read (any case); blank names and relationship paths are skipped
     * @return the snapshot; every requested simple field is present as readable, inaccessible or missing
     * @throws IllegalArgumentException when objectApiName or recordId is missing
     * @throws FlowProofException when the object is unknown or not readable, the Id belongs to another
     *         object, or the record cannot be read
     */
    public FlowProofRecordSnapshot getSnapshot(String objectApiName, Id recordId, Set<String> fieldApiNames) {
        if (String.isBlank(objectApiName) || recordId == null) {
            throw new IllegalArgumentException('An object API name and a record Id are required.');
        }
        Schema.DescribeSObjectResult objectDescribe = describeObject(objectApiName);
        if (recordId.getSObjectType() != objectDescribe.getSObjectType()) {
            throw new FlowProofException('The selected record is not a ' + objectDescribe.getLabel() + ' record.');
        }
        if (!objectDescribe.isAccessible()) {
            throw new FlowProofException('You do not have access to ' + objectDescribe.getLabelPlural() + '.');
        }

        FlowProofRecordSnapshot snapshot = new FlowProofRecordSnapshot(objectDescribe.getName());
        List<Schema.DescribeFieldResult> readableFields = classifyFields(
            objectDescribe,
            fieldApiNames ?? new Set<String>(),
            snapshot
        );
        Schema.DescribeFieldResult nameField = readableNameField(objectDescribe);
        List<Schema.DescribeFieldResult> queriedFields = new List<Schema.DescribeFieldResult>(readableFields);
        if (nameField != null) {
            queriedFields.add(nameField);
        }
        SObject record = queryRecord(objectDescribe.getName(), recordId, queriedFields);
        for (Schema.DescribeFieldResult field : readableFields) {
            snapshot.putValue(field.getName(), field.getType().name(), record.get(field.getName()));
        }
        if (nameField != null) {
            snapshot.recordName = String.valueOf(record.get(nameField.getName()));
        }
        return snapshot;
    }

    /**
     * @param objectDescribe the object's describe result
     * @return the object's name field (Name, CaseNumber, ...) when the user can read it, else null
     */
    private static Schema.DescribeFieldResult readableNameField(Schema.DescribeSObjectResult objectDescribe) {
        for (Schema.SObjectField token : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField()) {
                return field.isAccessible() ? field : null;
            }
        }
        return null;
    }

    private static Schema.DescribeSObjectResult describeObject(String objectApiName) {
        try {
            return Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (InvalidParameterValueException e) {
            throw new FlowProofException('Salesforce has no object named ' + objectApiName + '.', e);
        }
    }

    /**
     * Records missing and inaccessible fields in the snapshot and returns the readable ones.
     * @param objectDescribe the object's describe result
     * @param fieldApiNames requested field names
     * @param snapshot snapshot to record missing and inaccessible fields in
     * @return describe results of the fields the user can read, without duplicates
     */
    private static List<Schema.DescribeFieldResult> classifyFields(
        Schema.DescribeSObjectResult objectDescribe,
        Set<String> fieldApiNames,
        FlowProofRecordSnapshot snapshot
    ) {
        Map<String, Schema.SObjectField> fieldsByName = objectDescribe.fields.getMap();
        Map<String, Schema.DescribeFieldResult> readableByName = new Map<String, Schema.DescribeFieldResult>();
        for (String requested : fieldApiNames) {
            if (String.isBlank(requested) || requested.contains('.')) {
                continue;
            }
            Schema.SObjectField token = fieldsByName.get(requested.toLowerCase());
            if (token == null) {
                snapshot.putMissing(requested);
                continue;
            }
            Schema.DescribeFieldResult field = token.getDescribe();
            if (!field.isAccessible()) {
                snapshot.putInaccessible(field.getName());
                continue;
            }
            readableByName.put(field.getName().toLowerCase(), field);
        }
        return readableByName.values();
    }

    private static SObject queryRecord(String objectName, Id recordId, List<Schema.DescribeFieldResult> fields) {
        Set<String> selected = new Set<String>{ 'Id' };
        for (Schema.DescribeFieldResult field : fields) {
            selected.add(field.getName());
        }
        String soql =
            'SELECT ' +
            String.join(new List<String>(selected), ', ') +
            ' FROM ' +
            objectName +
            ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows;
        try {
            rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.USER_MODE
            );
        } catch (QueryException e) {
            throw new FlowProofException('FlowProof could not read the record with your permissions.', e);
        }
        if (rows.isEmpty()) {
            throw new FlowProofException('The record was not found, or you do not have access to it.');
        }
        return rows[0];
    }
}
