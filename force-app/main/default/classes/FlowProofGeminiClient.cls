/**
 * Calls the Gemini API through the Gemini_API named credential. The API key lives only in the
 * Gemini_API external credential (entered by an admin in Setup); this class never sees it.
 * Sends text only, asks for a JSON answer, and never lets Gemini call tools or change anything.
 *
 * @example
 * String answer = new FlowProofGeminiClient().generateJson('gemini-3.8-flash', instructions, facts, schema);
 */
public with sharing class FlowProofGeminiClient {
    @TestVisible
    private static final String MODELS_PATH = 'callout:Gemini_API/v1beta/models/';
    private static final Pattern MODEL_PATTERN = Pattern.compile('[a-z0-9][a-z0-9.\\-]{0,62}');
    private static final Integer TIMEOUT_MS = 60000;
    private static final Integer MAX_OUTPUT_TOKENS = 4096;
    private static final Integer ERROR_DETAIL_LIMIT = 300;
    private static final String KEY_STEP = 'An admin saves the Gemini API key in Setup > Named Credentials > External Credentials > Gemini API > Principals.';

    /**
     * Asks a Gemini model for a JSON answer.
     * @param model model code, e.g. gemini-3.8-flash
     * @param systemInstruction fixed rules for the model
     * @param userText the content to answer about
     * @param responseSchema schema the answer must follow (Gemini Schema format)
     * @return the answer text (JSON)
     * @throws FlowProofException with a user-safe message when Gemini cannot be reached or does not answer
     */
    public String generateJson(
        String model,
        String systemInstruction,
        String userText,
        Map<String, Object> responseSchema
    ) {
        Map<String, Object> body = new Map<String, Object>{
            'systemInstruction' => new Map<String, Object>{
                'parts' => new List<Object>{ textPart(systemInstruction) }
            },
            'contents' => new List<Object>{
                new Map<String, Object>{ 'role' => 'user', 'parts' => new List<Object>{ textPart(userText) } }
            },
            'generationConfig' => new Map<String, Object>{
                'responseMimeType' => 'application/json',
                'responseSchema' => responseSchema,
                'maxOutputTokens' => MAX_OUTPUT_TOKENS,
                'thinkingConfig' => new Map<String, Object>{ 'thinkingLevel' => 'low' }
            }
        };
        HttpRequest request = newRequest(model, ':generateContent', 'POST');
        request.setHeader('Content-Type', 'application/json');
        request.setBody(JSON.serialize(body));
        HttpResponse response = send(request);
        if (response.getStatusCode() != 200) {
            throw new FlowProofException(errorMessage(model, response));
        }
        return answerText(response.getBody());
    }

    /**
     * Checks that the key works and the model exists, without generating anything (reads the model's details).
     * Never throws; the status explains what to do.
     * @param model model code
     * @return the connection status
     */
    public FlowProofConnectionStatus testConnection(String model) {
        try {
            HttpResponse response = send(newRequest(model, '', 'GET'));
            if (response.getStatusCode() == 200) {
                return new FlowProofConnectionStatus(
                    'CONNECTED',
                    'Gemini is reachable and the model ' + model + ' is available.'
                );
            }
            return new FlowProofConnectionStatus('NOT_AUTHORIZED', errorMessage(model, response));
        } catch (FlowProofException e) {
            return new FlowProofConnectionStatus('NOT_CONFIGURED', e.getMessage());
        }
    }

    private static HttpRequest newRequest(String model, String action, String method) {
        if (String.isBlank(model) || !MODEL_PATTERN.matcher(model).matches()) {
            throw new FlowProofException(
                'The AI model in FlowProof settings is not a valid Gemini model code (for example gemini-3.8-flash).'
            );
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint(MODELS_PATH + model + action);
        request.setMethod(method);
        request.setTimeout(TIMEOUT_MS);
        return request;
    }

    private static HttpResponse send(HttpRequest request) {
        try {
            return new Http().send(request);
        } catch (CalloutException e) {
            throw new FlowProofException(
                'FlowProof could not reach Gemini through the Gemini_API named credential. ' +
                    KEY_STEP +
                    ' Users also need the FlowProof User permission set.',
                e
            );
        }
    }

    private static String answerText(String body) {
        Map<String, Object> response;
        try {
            response = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (JSONException e) {
            throw new FlowProofException('Gemini\'s response could not be read.', e);
        } catch (TypeException e) {
            throw new FlowProofException('Gemini\'s response could not be read.', e);
        }
        String blockReason = asString(asMap(response.get('promptFeedback'))?.get('blockReason'));
        if (blockReason != null) {
            throw new FlowProofException('Gemini declined the request (' + blockReason + ').');
        }
        List<Object> candidates = asList(response.get('candidates'));
        if (candidates.isEmpty()) {
            throw new FlowProofException('Gemini returned no answer. Try again.');
        }
        Map<String, Object> candidate = asMap(candidates[0]) ?? new Map<String, Object>();
        String finishReason = asString(candidate.get('finishReason'));
        if (finishReason == 'MAX_TOKENS') {
            throw new FlowProofException('Gemini\'s answer was cut off. Try again.');
        }
        if (finishReason != null && finishReason != 'STOP') {
            throw new FlowProofException('Gemini stopped without a complete answer (' + finishReason + ').');
        }
        List<String> texts = new List<String>();
        for (Object item : asList(asMap(candidate.get('content'))?.get('parts'))) {
            Map<String, Object> part = asMap(item) ?? new Map<String, Object>();
            // Thought summaries are the model's reasoning, not the answer.
            if (part.get('thought') != true && part.get('text') instanceof String) {
                texts.add((String) part.get('text'));
            }
        }
        if (texts.isEmpty()) {
            throw new FlowProofException('Gemini returned an empty answer. Try again.');
        }
        return String.join(texts, '');
    }

    private static String errorMessage(String model, HttpResponse response) {
        Integer status = response.getStatusCode();
        String detail = errorDetail(response.getBody());
        if (status == 400 && detail.containsIgnoreCase('API key')) {
            return 'Gemini rejected the API key. ' + KEY_STEP;
        }
        if (status == 401 || status == 403) {
            return 'Gemini refused the request (HTTP ' +
                status +
                '). Check that the API key is valid and allowed to use the Gemini API. ' +
                KEY_STEP;
        }
        if (status == 404) {
            return 'Gemini does not offer the model ' +
                model +
                '. An admin can change the model in FlowProof settings.';
        }
        if (status == 429) {
            return 'The Gemini API key has reached its usage limit. Try again later, or check its quota in Google AI Studio.';
        }
        if (status >= 500) {
            return 'Gemini is unavailable right now (HTTP ' + status + '). Try again in a minute.';
        }
        return 'Gemini rejected the request (HTTP ' + status + ')' + (String.isBlank(detail) ? '.' : ': ' + detail);
    }

    // Google's error message; it describes the problem and never contains the key.
    private static String errorDetail(String body) {
        try {
            Map<String, Object> error = asMap(asMap(JSON.deserializeUntyped(body ?? ''))?.get('error'));
            return (asString(error?.get('message')) ?? '').abbreviate(ERROR_DETAIL_LIMIT);
        } catch (JSONException e) {
            return '';
        }
    }

    private static Map<String, Object> textPart(String text) {
        return new Map<String, Object>{ 'text' => text };
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String asString(Object value) {
        return value instanceof String ? (String) value : null;
    }
}
