/**
 * Adds an optional Gemini explanation to a saved investigation. Runs in its own transaction after
 * the investigation is saved: reads the saved result, sends minimized facts to Gemini (callout),
 * checks the answer, then stores it on the investigation (DML). The deterministic findings are
 * never changed, and nothing else is: Gemini cannot modify records, deploy metadata or run code.
 *
 * @example
 * FlowProofAiExplanation explanation = new FlowProofAiService().explain(investigationId, false);
 */
public with sharing class FlowProofAiService {
    private static final String TURNED_OFF = 'AI explanations are turned off. An admin can turn them on in Setup > Custom Metadata Types > FlowProof Setting > Manage Records > Default (AI Explanations Enabled).';

    private final FlowProofGeminiClient client;
    private final FlowProofResultService results;
    private final FlowProofSettings settings;

    /**
     * Creates a service that uses the FlowProof settings and the Gemini_API named credential.
     */
    public FlowProofAiService() {
        this(new FlowProofGeminiClient(), new FlowProofResultService(), FlowProofSettings.load());
    }

    /**
     * @param client Gemini client
     * @param results reads and updates saved investigations
     * @param settings FlowProof settings
     */
    @TestVisible
    private FlowProofAiService(
        FlowProofGeminiClient client,
        FlowProofResultService results,
        FlowProofSettings settings
    ) {
        this.client = client;
        this.results = results;
        this.settings = settings;
    }

    /**
     * Returns the investigation's AI explanation, generating and saving it when needed.
     * @param investigationId FlowProof_Investigation__c Id
     * @param regenerate true to replace an existing explanation
     * @return the explanation
     * @throws FlowProofException when AI is turned off, the investigation cannot be read, or Gemini does not answer
     */
    public FlowProofAiExplanation explain(Id investigationId, Boolean regenerate) {
        if (settings?.aiEnabled != true) {
            throw new FlowProofException(TURNED_OFF);
        }
        FlowProofInvestigationResult result = results.load(investigationId);
        if (result.aiExplanation != null && regenerate != true) {
            return result.aiExplanation;
        }
        Boolean shareValues = settings.aiSendFieldValues == true;
        FlowProofAiPromptBuilder prompt = new FlowProofAiPromptBuilder(result, shareValues);
        String answer = client.generateJson(
            settings.aiModel,
            prompt.systemInstruction(),
            prompt.userContent(),
            prompt.responseSchema()
        );
        FlowProofAiExplanation explanation = FlowProofAiExplanation.fromModelJson(answer, prompt.validRefs());
        explanation.model = settings.aiModel;
        explanation.generatedAt = Datetime.now();
        explanation.fieldValuesShared = shareValues;
        results.saveAiExplanation(investigationId, explanation);
        return explanation;
    }

    /**
     * Checks that Gemini is reachable with the configured key and model. Works while AI explanations
     * are turned off, so an admin can test the key first; sends no investigation data.
     * @return the connection status
     */
    public FlowProofConnectionStatus testConnection() {
        return client.testConnection(settings?.aiModel);
    }
}
