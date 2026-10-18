/**
 * Small client for this org's Tooling API through the FlowProof_Org_API named credential
 * (per-user OAuth), so every call runs with the signed-in user's own permissions. Used for the
 * debug-log steps of "Record a test save".
 *
 * @example
 * List<Map<String, Object>> rows = new FlowProofToolingClient().query('SELECT Id FROM DebugLevel LIMIT 1');
 */
public with sharing class FlowProofToolingClient {
    @TestVisible
    private static final String TOOLING_PATH = 'callout:FlowProof_Org_API/services/data/v68.0/tooling/';
    private static final Integer TIMEOUT_MS = 30000;
    private static final Integer ERROR_DETAIL_LIMIT = 300;

    /**
     * Runs a Tooling SOQL query (first page only).
     * @param soql the query; callers build it from validated values only
     * @return the records as untyped maps
     * @throws FlowProofMetadataException when the call fails
     */
    public List<Map<String, Object>> query(String soql) {
        Map<String, Object> body = asMap(
            JSON.deserializeUntyped(send('GET', 'query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'), null))
        );
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (
            Object row : body.get('records') instanceof List<Object>
                ? (List<Object>) body.get('records')
                : new List<Object>()
        ) {
            rows.add(asMap(row));
        }
        return rows;
    }

    /**
     * Creates a Tooling record.
     * @param sobjectType e.g. TraceFlag
     * @param fields field values
     * @return the new record's Id
     */
    public String create(String sobjectType, Map<String, Object> fields) {
        return (String) asMap(JSON.deserializeUntyped(send('POST', 'sobjects/' + sobjectType, JSON.serialize(fields))))
            .get('id');
    }

    /**
     * Updates a Tooling record.
     * @param sobjectType e.g. TraceFlag
     * @param recordId the record
     * @param fields field values to change
     */
    public void updateRecord(String sobjectType, Id recordId, Map<String, Object> fields) {
        send('PATCH', 'sobjects/' + sobjectType + '/' + recordId, JSON.serialize(fields));
    }

    /**
     * Deletes a Tooling record.
     * @param sobjectType e.g. TraceFlag
     * @param recordId the record
     */
    public void deleteRecord(String sobjectType, Id recordId) {
        send('DELETE', 'sobjects/' + sobjectType + '/' + recordId, null);
    }

    /**
     * Reads a debug log's text.
     * @param logId ApexLog Id
     * @return the log body
     */
    public String getLogBody(Id logId) {
        return send('GET', 'sobjects/ApexLog/' + logId + '/Body', null);
    }

    private static String send(String method, String path, String body) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(TOOLING_PATH + path);
        request.setTimeout(TIMEOUT_MS);
        if (method == 'PATCH') {
            // Apex HTTP has no PATCH; the REST API accepts it as an override on POST.
            request.setMethod('POST');
            request.setEndpoint(request.getEndpoint() + '?_HttpMethod=PATCH');
        } else {
            request.setMethod(method);
        }
        if (body != null) {
            request.setHeader('Content-Type', 'application/json');
            request.setBody(body);
        }
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            throw new FlowProofMetadataException(
                    'FlowProof could not reach the org API through the FlowProof_Org_API named credential. ' +
                    'Authorize FlowProof once: Settings > External Credentials > FlowProof Org EC > Allow Access.',
                    e
                )
                .withReason(FlowProofMetadataException.Reason.CONNECTION_FAILED);
        }
        Integer status = response.getStatusCode();
        if (status >= 200 && status < 300) {
            return response.getBody();
        }
        String detail = errorDetail(response.getBody());
        if (status == 401) {
            throw new FlowProofMetadataException(
                    'The org API refused the request (HTTP 401). Authorize FlowProof again: Settings > External Credentials > FlowProof Org EC > Allow Access.'
                )
                .withReason(FlowProofMetadataException.Reason.NOT_AUTHORIZED);
        }
        if (status == 403 || detail.containsIgnoreCase('insufficient')) {
            throw new FlowProofMetadataException(
                    'You need permission to manage debug logs for this (ask an admin; it is usually included in "View All Data" or "Manage Users"). ' +
                    detail
                )
                .withReason(FlowProofMetadataException.Reason.NOT_AUTHORIZED);
        }
        throw new FlowProofMetadataException('The org API returned HTTP ' + status + '. ' + detail)
            .withReason(FlowProofMetadataException.Reason.UNAVAILABLE);
    }

    // The API's own message, e.g. "This entity is already being traced."; never contains secrets.
    private static String errorDetail(String body) {
        try {
            Object parsed = JSON.deserializeUntyped(body ?? '');
            Object first = parsed instanceof List<Object> && !((List<Object>) parsed).isEmpty()
                ? ((List<Object>) parsed)[0]
                : parsed;
            return (String.valueOf(asMap(first).get('message') ?? '')).abbreviate(ERROR_DETAIL_LIMIT);
        } catch (JSONException e) {
            return '';
        }
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }
}
