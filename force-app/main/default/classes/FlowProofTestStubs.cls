/**
 * Reusable test doubles for FlowProof tests: a Flow catalog query stub, a Flow definition stub
 * and an HTTP mock. Kept in one place so service and controller tests share them.
 */
@IsTest
public class FlowProofTestStubs {
    /** Built at runtime: a syntactically valid Flow version Id that exists in no org. */
    public static final String VERSION_ID = '301' + '0'.repeat(11) + '1AAA';

    /**
     * A FlowDefinitionView row for an active, record-triggered after-save Flow on Opportunity.
     * @param apiName Flow API name
     * @return the row (built through JSON because its fields are read-only)
     */
    public static FlowDefinitionView activeOpportunityFlow(String apiName) {
        return opportunityFlow(apiName, true);
    }

    /**
     * A FlowDefinitionView row for a record-triggered after-save Flow on Opportunity.
     * @param apiName Flow API name
     * @param isActive true for an active Flow; an inactive one has only a latest version
     * @return the row (built through JSON because its fields are read-only)
     */
    public static FlowDefinitionView opportunityFlow(String apiName, Boolean isActive) {
        return (FlowDefinitionView) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'FlowDefinitionView' },
                    'ApiName' => apiName,
                    'Label' => apiName.replace('_', ' '),
                    'IsActive' => isActive,
                    'ActiveVersionId' => isActive ? VERSION_ID : null,
                    'LatestVersionId' => VERSION_ID,
                    'ProcessType' => 'AutoLaunchedFlow',
                    'TriggerType' => 'RecordAfterSave',
                    'RecordTriggerType' => 'CreateAndUpdate',
                    'TriggerObjectOrEventId' => 'Opportunity',
                    'TriggerObjectOrEventLabel' => 'Opportunity'
                }
            ),
            FlowDefinitionView.class
        );
    }

    /**
     * @param apiName object API name
     * @return an EntityDefinition row whose DurableId is the API name
     */
    public static EntityDefinition entity(String apiName) {
        return (EntityDefinition) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'EntityDefinition' },
                    'DurableId' => apiName,
                    'QualifiedApiName' => apiName
                }
            ),
            EntityDefinition.class
        );
    }

    /**
     * Full metadata of an after-save Flow on Opportunity with one Create Records element and no
     * fault path, which the health checks report.
     * @return untyped Flow metadata
     */
    public static Map<String, Object> metadataWithoutFaultPath() {
        return new Map<String, Object>{
            'label' => 'Opportunity Onboarding',
            'start' => new Map<String, Object>{
                'object' => 'Opportunity',
                'triggerType' => 'RecordAfterSave',
                'recordTriggerType' => 'CreateAndUpdate',
                'doesRequireRecordChangedToMeetCriteria' => true,
                'connector' => new Map<String, Object>{ 'targetReference' => 'Create_Task' }
            },
            'recordCreates' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Create_Task', 'label' => 'Create Task', 'object' => 'Task' }
            }
        };
    }

    /**
     * StageName = Closed Won AND Amount > 10000 AND Type = New Customer, after save on Opportunity.
     * @return the start element
     */
    public static FlowProofFlowModel.FlowStart onboardingStart() {
        FlowProofFlowModel.FlowStart start = new FlowProofFlowModel.FlowStart();
        start.objectApiName = 'Opportunity';
        start.triggerType = 'RecordAfterSave';
        start.recordTriggerType = 'CreateAndUpdate';
        start.filterLogic = 'and';
        start.filters.add(
            new FlowProofFlowModel.Condition(1, 'StageName', 'EqualTo', FlowProofFlowModel.stringValue('Closed Won'))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(2, 'Amount', 'GreaterThan', FlowProofFlowModel.numberValue(10000))
        );
        start.filters.add(
            new FlowProofFlowModel.Condition(3, 'Type', 'EqualTo', FlowProofFlowModel.stringValue('New Customer'))
        );
        return start;
    }

    /**
     * An investigation service whose catalog returns one Flow and whose definition source returns the given start.
     * @param flow the Flow row the catalog returns
     * @param start the start element the definition source returns
     * @return the service (uses the real record service)
     */
    public static FlowProofInvestigationService investigationService(
        FlowDefinitionView flow,
        FlowProofFlowModel.FlowStart start
    ) {
        CatalogQueries queries = new CatalogQueries();
        queries.flows.add(flow);
        queries.entities.add(entity('Opportunity'));
        return new FlowProofInvestigationService(
            new FlowProofFlowCatalogService(queries),
            new Definitions(start),
            new FlowProofRecordService()
        );
    }

    /**
     * Creates an Opportunity and investigates it against the onboarding conditions (stubbed Flow
     * metadata, no callouts). The result is not saved.
     * @param name Opportunity name
     * @param stageName stage
     * @param amount amount
     * @return the unsaved result
     */
    public static FlowProofInvestigationResult investigateOpportunity(String name, String stageName, Decimal amount) {
        Opportunity opportunity = FlowProofTestDataFactory.createOpportunity(name, stageName, amount, true);
        return investigationService(activeOpportunityFlow('Opportunity_Onboarding'), onboardingStart())
            .investigate(new FlowProofInvestigationRequest('Opportunity', opportunity.Id, 'Opportunity_Onboarding'));
    }

    /**
     * @param enabled whether AI explanations are on
     * @return settings for the default Gemini model, with field values not shared
     */
    public static FlowProofSettings aiSettings(Boolean enabled) {
        FlowProofSettings settings = new FlowProofSettings();
        settings.aiEnabled = enabled;
        settings.aiModel = 'gemini-3.8-flash';
        settings.aiSendFieldValues = false;
        return settings;
    }

    /**
     * @param answerText the model's answer
     * @return a generateContent response body with one finished candidate
     */
    public static String geminiResponse(String answerText) {
        return JSON.serialize(
            new Map<String, Object>{
                'candidates' => new List<Object>{
                    new Map<String, Object>{
                        'finishReason' => 'STOP',
                        'content' => new Map<String, Object>{
                            'role' => 'model',
                            'parts' => new List<Object>{ new Map<String, Object>{ 'text' => answerText } }
                        }
                    }
                }
            }
        );
    }

    /**
     * @return a valid explanation answer citing the failing-conditions finding and condition 3
     */
    public static String geminiAnswer() {
        return JSON.serialize(
            new Map<String, Object>{
                'summary' => 'The Flow did not act because the Type condition is not met.',
                'keyPoints' => new List<Object>{
                    new Map<String, Object>{
                        'text' => 'Type must be New Customer.',
                        'basedOn' => new List<String>{ 'CONDITIONS_NOT_MET', 'C3' }
                    }
                },
                'nextSteps' => new List<String>{ 'Set Type to New Customer if that is correct for this deal.' },
                'caveats' => new List<String>{ 'Whether the Flow ran at the last save is not confirmed.' }
            }
        );
    }

    /** Catalog query stub returning fixed rows. */
    public class CatalogQueries extends FlowProofFlowCatalogService.FlowQueries {
        /** Rows returned for every Flow query. */
        public List<FlowDefinitionView> flows = new List<FlowDefinitionView>();
        /** Rows returned for entity lookups. */
        public List<EntityDefinition> entities = new List<EntityDefinition>();

        public override List<FlowDefinitionView> findAllRecordTriggeredFlows() {
            return flows;
        }

        public override List<EntityDefinition> findEntitiesByDurableId(Set<String> durableIds) {
            return entities;
        }

        public override List<EntityDefinition> findEntity(String objectApiName) {
            return entities;
        }

        public override List<FlowDefinitionView> findRecordTriggeredFlows(String triggerObjectDurableId) {
            return flows;
        }

        public override List<FlowDefinitionView> findFlowByApiName(String flowApiName) {
            return flows;
        }
    }

    /** Definition source stub returning a fixed start element and optional full metadata. */
    public class Definitions implements FlowProofFlowDefinitionSource {
        private final FlowProofFlowModel.FlowStart start;
        /** Full metadata to return (for health checks); null by default. */
        public Map<String, Object> metadata;
        /** Version Ids requested, in order. */
        public List<String> requestedVersionIds = new List<String>();

        /**
         * @param start the start element to return
         */
        public Definitions(FlowProofFlowModel.FlowStart start) {
            this.start = start;
        }

        public FlowProofFlowDefinition getDefinition(Id flowVersionId) {
            requestedVersionIds.add(flowVersionId);
            return new FlowProofFlowDefinition(start, metadata);
        }
    }

    /**
     * A debug log of one save, in the format Salesforce writes with Workflow at FINER: one
     * record-triggered Flow ran for the record and created a Task.
     * @param recordId the saved record
     * @param flowLabel the Flow's label
     * @param versionId15 the Flow version Id (15 characters)
     * @return the log text
     */
    public static String flowSaveLog(Id recordId, String flowLabel, String versionId15) {
        String interview = '1240af9156dfd0f4ef39278b84661a14e519f14-7522';
        return String.join(
            new List<String>{
                '68.0 APEX_CODE,NONE;DB,INFO;VALIDATION,INFO;WORKFLOW,FINER',
                '03:17:05.89 (89457080)|EXECUTION_STARTED',
                '03:17:05.89 (89541421)|CODE_UNIT_STARTED|[EXTERNAL]|Flow:Opportunity',
                '03:17:05.105 (105229296)|FLOW_CREATE_INTERVIEW_BEGIN|00D000000000001|300000000000001|' + versionId15,
                '03:17:05.105 (105438358)|FLOW_CREATE_INTERVIEW_END|' +
                interview +
                '|' +
                flowLabel,
                '03:17:05.107 (107726890)|FLOW_START_INTERVIEWS_BEGIN|1',
                '03:17:05.107 (107864291)|FLOW_START_INTERVIEW_BEGIN|' +
                interview +
                '|' +
                flowLabel,
                '03:17:05.107 (109103743)|FLOW_VALUE_ASSIGNMENT|' +
                interview +
                '|$Record|{Id=' +
                recordId +
                ', IsDeleted=false, Name=Synthetic, StageName=Closed Won}',
                '03:17:05.107 (109200000)|FLOW_ELEMENT_BEGIN|' +
                interview +
                '|FlowDecision|Is_Large',
                '03:17:05.107 (109300000)|FLOW_RULE_DETAIL|' +
                interview +
                '|Large_Deal|true',
                '03:17:05.107 (109379645)|FLOW_ELEMENT_BEGIN|' +
                interview +
                '|FlowRecordCreate|Create_Onboarding_Task',
                '03:17:05.107 (109554147)|FLOW_ELEMENT_END|' +
                interview +
                '|FlowRecordCreate|Create_Onboarding_Task',
                '03:17:05.107 (109645638)|FLOW_START_INTERVIEW_END|' +
                interview +
                '|' +
                flowLabel,
                '03:17:05.107 (288563407)|FLOW_INTERVIEW_FINISHED|' +
                interview +
                '|' +
                flowLabel,
                '03:17:05.89 (291764917)|CODE_UNIT_FINISHED|Flow:Opportunity',
                '03:17:05.89 (291784007)|EXECUTION_FINISHED'
            },
            '\n'
        );
    }

    /** HTTP mock that answers by method and URL fragment; records the requests it answers. */
    public class RoutingMock implements HttpCalloutMock {
        private final List<List<Object>> routes = new List<List<Object>>();
        /** Requests answered, in order. */
        public List<HttpRequest> requests = new List<HttpRequest>();

        /**
         * Adds a route; the first matching route answers.
         * @param method HTTP method (GET, POST, DELETE)
         * @param urlFragment text the URL-decoded endpoint must contain
         * @param status status to return
         * @param body body to return
         * @return this mock, for chaining
         */
        public RoutingMock route(String method, String urlFragment, Integer status, String body) {
            routes.add(new List<Object>{ method, urlFragment, status, body });
            return this;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            String endpoint = EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(404);
            response.setBody('[{"message":"No route for ' + request.getMethod() + ' ' + endpoint + '"}]');
            for (List<Object> route : routes) {
                if (request.getMethod() == (String) route[0] && endpoint.contains((String) route[1])) {
                    response.setStatusCode((Integer) route[2]);
                    response.setBody((String) route[3]);
                    break;
                }
            }
            return response;
        }
    }

    /** HTTP mock returning a fixed status and body; records the requests it answers. */
    public class FixedResponse implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        /** Requests answered, in order. */
        public List<HttpRequest> requests = new List<HttpRequest>();

        /**
         * @param status HTTP status to return
         * @param body body to return
         */
        public FixedResponse(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }
}
