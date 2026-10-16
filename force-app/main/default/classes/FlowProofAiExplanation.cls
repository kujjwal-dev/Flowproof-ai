/**
 * A plain-language explanation of an investigation, written by Gemini from FlowProof's findings.
 * It is an aid, not evidence: the deterministic findings stay the source of truth. Key points must
 * cite the findings or conditions they rely on; points that cite nothing FlowProof found are
 * dropped (and counted) before the explanation is shown or saved.
 */
public with sharing class FlowProofAiExplanation {
    private static final Integer SUMMARY_LIMIT = 1200;
    private static final Integer ITEM_LIMIT = 600;
    private static final Integer MAX_POINTS = 5;
    private static final Integer MAX_STEPS = 5;
    private static final Integer MAX_CAVEATS = 3;
    private static final String UNREADABLE = 'Gemini\'s answer was not in the expected format. Try again.';

    /** Short overall explanation. */
    @AuraEnabled
    public String summary { get; set; }
    /** Key points, each citing the findings or conditions it relies on. */
    @AuraEnabled
    public List<KeyPoint> keyPoints { get; set; }
    /** Suggested next steps for an admin. */
    @AuraEnabled
    public List<String> nextSteps { get; set; }
    /** Limits of the explanation. */
    @AuraEnabled
    public List<String> caveats { get; set; }
    /** Number of key points removed because they cited nothing FlowProof found. */
    @AuraEnabled
    public Integer droppedPointCount { get; set; }
    /** Gemini model that wrote the explanation. */
    @AuraEnabled
    public String model { get; set; }
    /** When the explanation was generated. */
    @AuraEnabled
    public Datetime generatedAt { get; set; }
    /** True when the record's field values were sent to Gemini. */
    @AuraEnabled
    public Boolean fieldValuesShared { get; set; }

    /**
     * Creates an empty explanation (also used for deserialization).
     */
    public FlowProofAiExplanation() {
        this.keyPoints = new List<KeyPoint>();
        this.nextSteps = new List<String>();
        this.caveats = new List<String>();
        this.droppedPointCount = 0;
        this.fieldValuesShared = false;
    }

    /**
     * Reads and checks the model's JSON answer.
     * @param modelJson the answer text, expected to be JSON matching the response schema
     * @param validRefs refs a key point may cite (rule codes and condition refs)
     * @return the explanation, with uncited key points and unknown refs removed
     * @throws FlowProofException when the answer is not usable
     */
    public static FlowProofAiExplanation fromModelJson(String modelJson, Set<String> validRefs) {
        if (String.isBlank(modelJson)) {
            throw new FlowProofException(UNREADABLE);
        }
        Map<String, Object> answer;
        try {
            answer = (Map<String, Object>) JSON.deserializeUntyped(modelJson);
        } catch (JSONException e) {
            throw new FlowProofException(UNREADABLE, e);
        } catch (TypeException e) {
            throw new FlowProofException(UNREADABLE, e);
        }
        FlowProofAiExplanation explanation = new FlowProofAiExplanation();
        explanation.summary = clean(answer.get('summary'), SUMMARY_LIMIT);
        if (String.isBlank(explanation.summary)) {
            throw new FlowProofException('Gemini\'s answer had no summary. Try again.');
        }
        for (Object item : asList(answer.get('keyPoints'))) {
            KeyPoint point = toKeyPoint(item, validRefs);
            if (point == null) {
                explanation.droppedPointCount++;
            } else if (explanation.keyPoints.size() < MAX_POINTS) {
                explanation.keyPoints.add(point);
            }
        }
        explanation.nextSteps = cleanList(answer.get('nextSteps'), MAX_STEPS);
        explanation.caveats = cleanList(answer.get('caveats'), MAX_CAVEATS);
        return explanation;
    }

    private static KeyPoint toKeyPoint(Object item, Set<String> validRefs) {
        Map<String, Object> raw = item instanceof Map<String, Object> ? (Map<String, Object>) item : null;
        String text = clean(raw?.get('text'), ITEM_LIMIT);
        if (String.isBlank(text)) {
            return null;
        }
        KeyPoint point = new KeyPoint();
        point.text = text;
        for (Object ref : asList(raw.get('basedOn'))) {
            String value = ref instanceof String ? ((String) ref).trim().toUpperCase() : null;
            if (value != null && validRefs.contains(value) && !point.basedOn.contains(value)) {
                point.basedOn.add(value);
            }
        }
        return point.basedOn.isEmpty() ? null : point;
    }

    private static List<String> cleanList(Object value, Integer maxItems) {
        List<String> items = new List<String>();
        for (Object item : asList(value)) {
            String text = clean(item, ITEM_LIMIT);
            if (String.isNotBlank(text) && items.size() < maxItems) {
                items.add(text);
            }
        }
        return items;
    }

    private static String clean(Object value, Integer maxLength) {
        return value instanceof String ? ((String) value).trim().abbreviate(maxLength) : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    /** One explained point and the findings or conditions it is based on. */
    public with sharing class KeyPoint {
        /** The point, in plain language. */
        @AuraEnabled
        public String text { get; set; }
        /** Rule codes (for example CONDITIONS_NOT_MET) and condition refs (for example C2). */
        @AuraEnabled
        public List<String> basedOn { get; set; }

        /**
         * Creates an empty key point.
         */
        public KeyPoint() {
            this.basedOn = new List<String>();
        }
    }
}
