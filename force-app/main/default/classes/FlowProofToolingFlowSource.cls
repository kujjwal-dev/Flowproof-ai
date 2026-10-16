/**
 * Reads a Flow version's start element through this org's Tooling API, using the
 * FlowProof_Org_API named credential (per-user OAuth). The query runs with the signed-in
 * user's own permissions, so FlowProof never shows a Flow definition the user couldn't read.
 *
 * Tooling API rule: Flow.Metadata can only be queried when the result has at most one row,
 * so the query always filters by a single version Id.
 *
 * @example
 * FlowProofFlowModel.FlowStart start = new FlowProofToolingFlowSource().getStart(summary.activeVersionId);
 */
public with sharing class FlowProofToolingFlowSource implements FlowProofFlowDefinitionSource {
    @TestVisible
    private static final String QUERY_PATH = 'callout:FlowProof_Org_API/services/data/v68.0/tooling/query?q=';
    private static final String FLOW_VERSION_PREFIX = '301';
    private static final Integer TIMEOUT_MS = 30000;
    private static final String AUTHORIZE_STEP = 'Authorize FlowProof once: Settings > External Credentials > FlowProof Org EC > Allow Access.';

    private final FlowProofFlowParser parser;

    /**
     * Creates a source that parses with the standard FlowProofFlowParser.
     */
    public FlowProofToolingFlowSource() {
        this(new FlowProofFlowParser());
    }

    /**
     * @param parser parser for the Flow.Metadata JSON
     */
    @TestVisible
    private FlowProofToolingFlowSource(FlowProofFlowParser parser) {
        this.parser = parser;
    }

    /**
     * Fetches one Flow version and returns its parsed start element with its full metadata.
     * @param flowVersionId Id of the Flow version (key prefix 301)
     * @return the definition
     * @throws IllegalArgumentException when the Id is missing or not a Flow version Id
     * @throws FlowProofMetadataException when the definition cannot be read; the reason says why
     */
    public FlowProofFlowDefinition getDefinition(Id flowVersionId) {
        String metadataJson = fetchMetadataJson(flowVersionId);
        return new FlowProofFlowDefinition(
            parser.parseStart(metadataJson),
            (Map<String, Object>) JSON.deserializeUntyped(metadataJson)
        );
    }

    /**
     * Fetches and parses only the start element of one Flow version.
     * @param flowVersionId Id of the Flow version (key prefix 301)
     * @return the parsed start element
     * @throws IllegalArgumentException when the Id is missing or not a Flow version Id
     * @throws FlowProofMetadataException when the definition cannot be read; the reason says why
     */
    public FlowProofFlowModel.FlowStart getStart(Id flowVersionId) {
        return parser.parseStart(fetchMetadataJson(flowVersionId));
    }

    private static String fetchMetadataJson(Id flowVersionId) {
        if (flowVersionId == null || !String.valueOf(flowVersionId).startsWith(FLOW_VERSION_PREFIX)) {
            throw new IllegalArgumentException('A Flow version Id (prefix 301) is required.');
        }
        HttpResponse response = send(flowVersionId);
        Integer status = response.getStatusCode();
        if (status == 401 || status == 403) {
            throw new FlowProofMetadataException(
                    'The org API refused the request (HTTP ' +
                        status +
                        '). ' +
                        AUTHORIZE_STEP +
                        ' Reading Flow definitions also needs the View Setup and Configuration permission.'
                )
                .withReason(FlowProofMetadataException.Reason.NOT_AUTHORIZED);
        }
        if (status != 200) {
            throw new FlowProofMetadataException(
                    'The org API returned HTTP ' + status + ' while reading the Flow definition.'
                )
                .withReason(FlowProofMetadataException.Reason.UNAVAILABLE);
        }
        return extractMetadataJson(response.getBody());
    }

    /**
     * Checks whether the current user can call the org API through FlowProof_Org_API, with a
     * minimal read-only Tooling query. Never throws; the status explains what to do.
     * @return the connection status
     */
    public FlowProofConnectionStatus testConnection() {
        try {
            Integer status = query('SELECT Id FROM FlowDefinition LIMIT 1').getStatusCode();
            if (status == 200) {
                return new FlowProofConnectionStatus('CONNECTED', 'FlowProof can read Flow definitions as you.');
            }
            if (status == 401 || status == 403) {
                return new FlowProofConnectionStatus(
                    'NOT_AUTHORIZED',
                    'The org API refused the request (HTTP ' + status + '). ' + AUTHORIZE_STEP
                );
            }
            return new FlowProofConnectionStatus(
                'UNAVAILABLE',
                'The org API returned HTTP ' + status + '. Try again in a minute.'
            );
        } catch (CalloutException e) {
            return new FlowProofConnectionStatus(
                'NOT_CONFIGURED',
                'FlowProof could not reach the org API through the FlowProof_Org_API named credential. ' +
                AUTHORIZE_STEP
            );
        }
    }

    private static HttpResponse query(String soql) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(QUERY_PATH + EncodingUtil.urlEncode(soql, 'UTF-8'));
        request.setMethod('GET');
        request.setTimeout(TIMEOUT_MS);
        return new Http().send(request);
    }

    private static HttpResponse send(Id flowVersionId) {
        try {
            return query('SELECT Metadata FROM Flow WHERE Id = \'' + flowVersionId + '\'');
        } catch (CalloutException e) {
            if (e.getMessage()?.containsIgnoreCase('uncommitted work') == true) {
                throw new FlowProofMetadataException(
                        'Salesforce does not allow FlowProof to call the org API after data was changed earlier in the same ' +
                        'transaction, so the Flow definition was not read.',
                        e
                    )
                    .withReason(FlowProofMetadataException.Reason.CALLOUT_AFTER_DML);
            }
            throw new FlowProofMetadataException(
                    'FlowProof could not reach the org API through the FlowProof_Org_API named credential. ' +
                        AUTHORIZE_STEP +
                        ' If that is already done, ask an admin to check the FlowProof Org API Access permission set.',
                    e
                )
                .withReason(FlowProofMetadataException.Reason.CONNECTION_FAILED);
        }
    }

    private static String extractMetadataJson(String body) {
        List<Object> records;
        try {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(body);
            records = (List<Object>) result.get('records');
        } catch (JSONException e) {
            throw invalidResponse(e);
        } catch (TypeException e) {
            throw invalidResponse(e);
        }
        if (records == null || records.isEmpty()) {
            throw new FlowProofMetadataException('No Flow version with that Id was found.')
                .withReason(FlowProofMetadataException.Reason.NOT_FOUND);
        }
        Object metadata = records[0] instanceof Map<String, Object>
            ? ((Map<String, Object>) records[0]).get('Metadata')
            : null;
        if (metadata == null) {
            throw new FlowProofMetadataException(
                    'Salesforce does not expose this Flow\'s definition (managed-package Flows hide their metadata).'
                )
                .withReason(FlowProofMetadataException.Reason.NO_METADATA);
        }
        return JSON.serialize(metadata);
    }

    private static FlowProofMetadataException invalidResponse(Exception cause) {
        return new FlowProofMetadataException('The org API response could not be read.', cause)
            .withReason(FlowProofMetadataException.Reason.INVALID_RESPONSE);
    }
}
