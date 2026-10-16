/**
 * Unit tests for FlowProofAiExplanation.fromModelJson: grounding key points in FlowProof's
 * findings, limits, and rejecting unusable answers.
 */
@IsTest
private class FlowProofAiExplanationTest {
    private static final Set<String> REFS = new Set<String>{ 'CONDITIONS_NOT_MET', 'C1', 'C2' };

    @IsTest
    static void shouldKeepPointsThatCiteFindings() {
        String answer = JSON.serialize(
            new Map<String, Object>{
                'summary' => '  Region is blank, so the Flow\'s conditions are not met.  ',
                'keyPoints' => new List<Object>{
                    point('Region must be North America.', new List<String>{ 'c2', 'C2', 'CONDITIONS_NOT_MET' }),
                    point('The Flow failed with an error last night.', new List<String>{ 'DEBUG_LOG' }),
                    point('No refs at all.', new List<String>())
                },
                'nextSteps' => new List<String>{ 'Set Region.', ' ' },
                'caveats' => new List<String>{ 'Run history is not confirmed.' }
            }
        );

        FlowProofAiExplanation explanation = FlowProofAiExplanation.fromModelJson(answer, REFS);

        Assert.areEqual('Region is blank, so the Flow\'s conditions are not met.', explanation.summary, 'Trimmed');
        Assert.areEqual(1, explanation.keyPoints.size(), 'Only grounded points are kept');
        Assert.areEqual(
            new List<String>{ 'C2', 'CONDITIONS_NOT_MET' },
            explanation.keyPoints[0].basedOn,
            'Refs are normalized and de-duplicated'
        );
        Assert.areEqual(2, explanation.droppedPointCount, 'Ungrounded points are counted');
        Assert.areEqual(new List<String>{ 'Set Region.' }, explanation.nextSteps, 'Blank steps are dropped');
        Assert.areEqual(1, explanation.caveats.size(), 'Caveats are kept');
    }

    @IsTest
    static void shouldLimitListsAndText() {
        List<Object> points = new List<Object>();
        List<String> steps = new List<String>();
        for (Integer i = 0; i < 8; i++) {
            points.add(point('Point ' + i, new List<String>{ 'C1' }));
            steps.add('Step ' + i);
        }
        String answer = JSON.serialize(
            new Map<String, Object>{
                'summary' => 'y'.repeat(5000),
                'keyPoints' => points,
                'nextSteps' => steps,
                'caveats' => steps
            }
        );

        FlowProofAiExplanation explanation = FlowProofAiExplanation.fromModelJson(answer, REFS);

        Assert.areEqual(5, explanation.keyPoints.size(), 'At most 5 key points');
        Assert.areEqual(5, explanation.nextSteps.size(), 'At most 5 next steps');
        Assert.areEqual(3, explanation.caveats.size(), 'At most 3 caveats');
        Assert.isTrue(explanation.summary.length() <= 1200, 'The summary is shortened');
        Assert.areEqual(0, explanation.droppedPointCount, 'Points over the limit are not counted as ungrounded');
    }

    @IsTest
    static void shouldRejectUnusableAnswers() {
        List<String> answers = new List<String>{ '', 'not json', '[1, 2]', '{"keyPoints": []}' };
        for (String answer : answers) {
            try {
                FlowProofAiExplanation.fromModelJson(answer, REFS);
                Assert.fail('Expected FlowProofException for: ' + answer);
            } catch (FlowProofException e) {
                Assert.isTrue(e.getMessage().contains('Try again'), 'The message should say what to do');
            }
        }
    }

    private static Map<String, Object> point(String text, List<String> basedOn) {
        return new Map<String, Object>{ 'text' => text, 'basedOn' => basedOn };
    }
}
