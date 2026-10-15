/**
 * Turns what an investigation learned into findings, each labelled with the strength of its
 * evidence and a recommended next step. Pure: no SOQL, DML or callouts.
 *
 * Rules never claim a Flow did or did not run: conclusions drawn from current record values
 * are at most SUPPORTED_HYPOTHESIS, and every result states that execution is not confirmed.
 *
 * @example
 * List<FlowProofFinding> findings = new FlowProofDiagnosticEngine().diagnose(context);
 */
public with sharing class FlowProofDiagnosticEngine {
    private static final String EDITOR_PATH = 'Setup > Flows';
    private static final String AUTHORIZE_STEP = 'Authorize FlowProof: Settings > External Credentials > FlowProof Org EC > Allow Access. If it still fails, ask an admin to check the FlowProof Org API Access permission set.';

    private List<FlowProofFinding> findings;

    /**
     * Applies every rule to the investigation context.
     * @param context what the investigation learned
     * @return findings sorted by severity, then category, then rule order
     * @throws IllegalArgumentException when context or its Flow summary is null
     */
    public List<FlowProofFinding> diagnose(FlowProofDiagnosticContext context) {
        if (context == null || context.flow == null) {
            throw new IllegalArgumentException('An investigation context with a Flow summary is required.');
        }
        findings = new List<FlowProofFinding>();
        checkActivation(context.flow);
        if (context.flow.isRecordTriggered != true) {
            add(notRecordTriggered(context.flow));
        } else if (context.metadataFailure != null) {
            add(metadataUnavailable(context));
        } else if (context.start != null) {
            checkTrigger(context);
            if (context.isSameObject() && context.evaluation != null) {
                checkConditions(context);
            }
        }
        add(executionNotConfirmed());
        findings.sort();
        return findings;
    }

    // ─── Flow configuration ──────────────────────────────────────────────

    private void checkActivation(FlowProofFlowSummary flow) {
        if (String.isBlank(flow.activeVersionId)) {
            add(
                new FlowProofFinding(
                        'NO_ACTIVE_VERSION',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.HIGH
                    )
                    .describe(
                        'The Flow has no active version',
                        flow.label +
                            ' has no active version, so Salesforce cannot run it for any record. ' +
                            'FlowProof evaluated the latest version for reference.',
                        'Activate the intended version in Flow Builder (' + EDITOR_PATH + ' > ' + flow.label + ').'
                    )
            );
        } else if (String.isNotBlank(flow.latestVersionId) && flow.latestVersionId != flow.activeVersionId) {
            add(
                new FlowProofFinding(
                        'NEWER_VERSION_INACTIVE',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.LOW
                    )
                    .describe(
                        'A newer version of the Flow is not active',
                        'The active version is not the latest one. FlowProof evaluated the active version, which is the one Salesforce runs.',
                        'If you expected behavior from the newer version, activate it in Flow Builder.'
                    )
            );
        }
    }

    private static FlowProofFinding notRecordTriggered(FlowProofFlowSummary flow) {
        return new FlowProofFinding(
                'NOT_RECORD_TRIGGERED',
                FlowProofFinding.Category.CONFIRMED,
                FlowProofFinding.Severity.HIGH
            )
            .describe(
                'This Flow does not run when records are saved',
                flow.label +
                    ' is not record-triggered (trigger type: ' +
                    (flow.triggerType ?? 'none') +
                    '). Saving a record never starts it.',
                'Check how this Flow is launched (a button, another Flow, a schedule or a platform event), ' +
                'or pick the record-triggered Flow that should have run.'
            );
    }

    private static FlowProofFinding metadataUnavailable(FlowProofDiagnosticContext context) {
        FlowProofFinding finding = new FlowProofFinding(
            'CONDITIONS_UNREADABLE',
            FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
            FlowProofFinding.Severity.HIGH
        );
        String detail = context.metadataFailureMessage ?? 'The Flow definition could not be read.';
        switch on context.metadataFailure {
            when CALLOUT_AFTER_DML {
                return finding.describe(
                    'FlowProof could not read the Flow\'s entry conditions',
                    detail,
                    'Run the investigation from the FlowProof AI app. If you call FlowProof from your own Apex, ' +
                    'run the investigation before saving any records in the same transaction.'
                );
            }
            when NOT_AUTHORIZED, CONNECTION_FAILED {
                return finding.describe(
                    'FlowProof could not read the Flow\'s entry conditions',
                    detail,
                    AUTHORIZE_STEP
                );
            }
            when NO_METADATA {
                return finding.describe(
                    'Salesforce hides this Flow\'s definition',
                    detail,
                    'Check the package documentation, or ask its vendor when this Flow runs.'
                );
            }
            when NOT_FOUND {
                return finding.describe(
                    'The Flow version was not found',
                    detail,
                    'Refresh and pick the Flow again; it may have been deleted.'
                );
            }
            when else {
                return finding.describe(
                    'FlowProof could not read the Flow\'s entry conditions',
                    detail,
                    'Try again in a minute. If it keeps failing, check Setup > Named Credentials > FlowProof Org API.'
                );
            }
        }
    }

    private void checkTrigger(FlowProofDiagnosticContext context) {
        FlowProofFlowModel.FlowStart start = context.start;
        if (!context.isSameObject()) {
            add(
                new FlowProofFinding(
                        'OBJECT_MISMATCH',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.HIGH
                    )
                    .describe(
                        'The Flow runs on a different object',
                        context.flow.label +
                            ' runs when ' +
                            start.objectApiName +
                            ' records are saved, but the investigated record is a ' +
                            context.recordObjectApiName +
                            '.',
                        'Pick a Flow that runs on ' +
                            context.recordObjectApiName +
                            ', or check whether a related ' +
                            start.objectApiName +
                            ' record was supposed to change.'
                    )
            );
            return;
        }
        FlowProofFinding event = triggerEventFinding(start);
        if (event != null) {
            add(event);
        }
        if (start.triggerType == 'RecordBeforeSave') {
            add(
                new FlowProofFinding(
                        'BEFORE_SAVE_FLOW',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.INFO
                    )
                    .describe(
                        'This is a fast field update (before-save) Flow',
                        'Before-save Flows can only update fields on the record being saved. They cannot create records, send emails or call actions.',
                        'If you expected a related record, email or action, look for an after-save Flow, Apex trigger or other automation.'
                    )
            );
        }
    }

    private static FlowProofFinding triggerEventFinding(FlowProofFlowModel.FlowStart start) {
        switch on start.recordTriggerType {
            when 'Create' {
                return new FlowProofFinding(
                        'RUNS_ON_CREATE_ONLY',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The Flow runs only when a record is created',
                        'Updates to an existing ' + start.objectApiName + ' never start this Flow.',
                        'If the record reached the expected state through an edit, this Flow will not run. ' +
                        'Consider the trigger "A record is created or updated".'
                    );
            }
            when 'Update' {
                return new FlowProofFinding(
                        'RUNS_ON_UPDATE_ONLY',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The Flow runs only when a record is updated',
                        'Creating a new ' +
                            start.objectApiName +
                            ' never starts this Flow, even if it already meets the conditions.',
                        'If the record was created in the expected state, this Flow did not run for it. ' +
                        'Consider the trigger "A record is created or updated".'
                    );
            }
            when 'Delete' {
                return new FlowProofFinding(
                        'RUNS_ON_DELETE_ONLY',
                        FlowProofFinding.Category.CONFIRMED,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The Flow runs only when a record is deleted',
                        'Creating or updating a ' + start.objectApiName + ' never starts this Flow.',
                        'Pick the Flow that should run on create or update.'
                    );
            }
            when else {
                return null;
            }
        }
    }

    // ─── Entry conditions ────────────────────────────────────────────────

    private void checkConditions(FlowProofDiagnosticContext context) {
        FlowProofEvaluationResult evaluation = context.evaluation;
        switch on evaluation.overall {
            when NOT_SATISFIED {
                add(conditionsNotMet(evaluation));
            }
            when SATISFIED {
                addConditionsMet(context);
            }
            when else {
                // INDETERMINATE: explained by the findings below.
            }
        }
        if (evaluation.logicType == 'FORMULA') {
            add(
                new FlowProofFinding(
                        'FORMULA_CONDITIONS',
                        FlowProofFinding.Category.UNSUPPORTED,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The entry conditions use a formula',
                        'FlowProof does not evaluate formula entry conditions yet.',
                        'Check the formula against the record\'s values, or debug the Flow in Flow Builder with this record.'
                    )
            );
        } else if (evaluation.logicType == 'CUSTOM') {
            add(
                new FlowProofFinding(
                        'CUSTOM_LOGIC',
                        FlowProofFinding.Category.UNSUPPORTED,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The conditions are combined with custom logic',
                        'FlowProof evaluated each condition but not the custom combination (' +
                            context.start.filterLogic +
                            ').',
                        'Apply the custom logic to the individual condition results.'
                    )
            );
        }
        addUnevaluated(evaluation);
    }

    private static FlowProofFinding conditionsNotMet(FlowProofEvaluationResult evaluation) {
        List<String> failing = new List<String>();
        for (FlowProofEvaluationResult.ConditionResult condition : evaluation.conditions) {
            if (condition.outcome == FlowProofEvaluationResult.ConditionOutcome.NO_MATCH) {
                failing.add(describeCondition(condition));
            }
        }
        return new FlowProofFinding(
                'CONDITIONS_NOT_MET',
                FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                FlowProofFinding.Severity.HIGH
            )
            .describe(
                'The record does not meet the Flow\'s entry conditions',
                'Based on the record\'s current values, these conditions fail: ' +
                    String.join(failing, '; ') +
                    '. ' +
                    'If the record had the same values when it was saved, the Flow would not have started. ' +
                    'Current values can differ from the values at the time of the save, so this is not proof.',
                'Check the failing fields on the record. If a value is wrong, correct it and save the record again; ' +
                'if the condition is wrong, update the Flow\'s entry conditions.'
            );
    }

    private void addConditionsMet(FlowProofDiagnosticContext context) {
        add(
            new FlowProofFinding(
                    'CONDITIONS_MET',
                    FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                    FlowProofFinding.Severity.INFO
                )
                .describe(
                    'The record meets the Flow\'s entry conditions',
                    'All entry conditions match the record\'s current values.',
                    'If the expected outcome still did not happen, check the findings below.'
                )
        );
        if (context.start.requiresRecordChangedToMeetCriteria == true) {
            add(
                new FlowProofFinding(
                        'ONLY_WHEN_UPDATED_TO_MEET',
                        FlowProofFinding.Category.SUPPORTED_HYPOTHESIS,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The Flow runs only when a record changes to meet the conditions',
                        'This Flow is set to run "only when a record is updated to meet the condition requirements". ' +
                        'If the record already met the conditions before the save you are investigating, the Flow did not run for that save.',
                        'Check whether the record met the conditions earlier (for example, field history). To run it again, ' +
                        'change a condition field so the record no longer matches, save, then change it back and save.'
                    )
            );
        } else {
            add(
                new FlowProofFinding(
                        'LOOK_INSIDE_FLOW',
                        FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
                        FlowProofFinding.Severity.MEDIUM
                    )
                    .describe(
                        'The entry conditions do not explain the problem',
                        'If the Flow started, the expected outcome depends on what happens after the start: a Decision element, a fault path or a failed action.',
                        'Debug the Flow in Flow Builder with this record, and check Flow error emails sent to the Flow\'s last modifier.'
                    )
            );
        }
    }

    private void addUnevaluated(FlowProofEvaluationResult evaluation) {
        Map<FlowProofEvaluationResult.ConditionOutcome, List<String>> byOutcome = new Map<FlowProofEvaluationResult.ConditionOutcome, List<String>>();
        for (FlowProofEvaluationResult.ConditionResult condition : evaluation.conditions) {
            if (!byOutcome.containsKey(condition.outcome)) {
                byOutcome.put(condition.outcome, new List<String>());
            }
            byOutcome.get(condition.outcome)
                .add('#' + condition.index + ' ' + condition.field + ' (' + condition.reason + ')');
        }
        addIfPresent(
            byOutcome.get(FlowProofEvaluationResult.ConditionOutcome.MISSING),
            new FlowProofFinding('MISSING_FIELDS', FlowProofFinding.Category.CONFIRMED, FlowProofFinding.Severity.HIGH),
            'The Flow refers to fields the object does not have',
            'Fix the Flow\'s entry conditions in Flow Builder.'
        );
        addIfPresent(
            byOutcome.get(FlowProofEvaluationResult.ConditionOutcome.INACCESSIBLE),
            new FlowProofFinding(
                'INACCESSIBLE_FIELDS',
                FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
                FlowProofFinding.Severity.MEDIUM
            ),
            'Some conditions use fields you cannot read',
            'Ask an admin for read access to these fields, or ask someone with access to run the investigation.'
        );
        addIfPresent(
            byOutcome.get(FlowProofEvaluationResult.ConditionOutcome.UNCERTAIN),
            new FlowProofFinding(
                'UNCERTAIN_CONDITIONS',
                FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
                FlowProofFinding.Severity.MEDIUM
            ),
            'Some conditions depend on Flow behavior FlowProof has not verified',
            'Debug the Flow in Flow Builder with this record to see how these conditions evaluate.'
        );
        addIfPresent(
            byOutcome.get(FlowProofEvaluationResult.ConditionOutcome.UNSUPPORTED),
            new FlowProofFinding(
                'UNSUPPORTED_CONDITIONS',
                FlowProofFinding.Category.UNSUPPORTED,
                FlowProofFinding.Severity.MEDIUM
            ),
            'Some conditions use constructs FlowProof does not evaluate yet',
            'Check these conditions manually against the record\'s values.'
        );
    }

    private void addIfPresent(List<String> conditions, FlowProofFinding finding, String title, String recommendation) {
        if (conditions != null && !conditions.isEmpty()) {
            add(finding.describe(title, 'Condition(s) ' + String.join(conditions, '; ') + '.', recommendation));
        }
    }

    private static FlowProofFinding executionNotConfirmed() {
        return new FlowProofFinding(
                'EXECUTION_NOT_CONFIRMED',
                FlowProofFinding.Category.INSUFFICIENT_EVIDENCE,
                FlowProofFinding.Severity.INFO
            )
            .describe(
                'Whether the Flow actually ran is not confirmed',
                'Salesforce keeps no per-record history of record-triggered Flow runs, so FlowProof cannot confirm whether this Flow ran ' +
                'when the record was saved. These findings use the Flow\'s current definition and the record\'s current values.',
                'To confirm, reproduce the save with a debug log (Setup > Debug Logs, Workflow category at FINER), ' +
                'or check Flow error emails sent to the Flow\'s last modifier.'
            );
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static String describeCondition(FlowProofEvaluationResult.ConditionResult condition) {
        return '#' +
            condition.index +
            ' ' +
            condition.field +
            ' ' +
            operatorPhrase(condition.operator) +
            ' ' +
            condition.expectedDisplay +
            ' (current value: ' +
            condition.actualDisplay +
            ')';
    }

    private static String operatorPhrase(String operator) {
        switch on (operator ?? '').toLowerCase() {
            when 'equalto' {
                return 'equals';
            }
            when 'notequalto' {
                return 'does not equal';
            }
            when 'greaterthan' {
                return 'is greater than';
            }
            when 'lessthan' {
                return 'is less than';
            }
            when 'greaterthanorequalto' {
                return 'is at least';
            }
            when 'lessthanorequalto' {
                return 'is at most';
            }
            when 'isnull' {
                return 'is null:';
            }
            when else {
                return operator;
            }
        }
    }

    private void add(FlowProofFinding finding) {
        finding.sortOrder = findings.size();
        findings.add(finding);
    }
}
