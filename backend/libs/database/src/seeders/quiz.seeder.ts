import {
  Prisma,
  QuestionScoringType,
  PrismaClient,
} from '../../generated/client';

// ─────────────────────────────────────────────────────────────
// Marriage Compatibility Quiz — 10 scenario-based questions.
// Replaces the retired 20-question OCEAN/Big-Five quiz entirely (not
// layered on top of it — see "Marriage Compatibility Quiz — 10 Question
// Spec", 2026-09-23). Single-select, 4 options per question, value 1-4.
// Scoring (per-question option-pair matrices, flags, the Q9 hard-axis
// ceiling) is NOT computed here — it belongs to the psychology module's
// pairwise compatibility engine (Phase 2). This seeder only stores the
// content and the pairRules metadata that engine will read.
// ─────────────────────────────────────────────────────────────

export interface OptionDefinition {
  key: 'A' | 'B' | 'C' | 'D';
  label: string;
  value: 1 | 2 | 3 | 4;
}

export interface PairRuleDefinition {
  pair: [string, string];
  type: 'flag' | 'dealbreaker';
  severity: 'soft' | 'medium' | 'high' | 'hard';
  message: string;
}

export interface QuestionDefinition {
  id: string;
  dimension: string;
  scoringType: QuestionScoringType;
  questionText: string;
  options: OptionDefinition[];
  pairRules: PairRuleDefinition[];
  order: number;
}

export const QUIZ_ID = 'marriage-compat-v1';

/**
 * Exported for the content-integrity spec, which checks these definitions
 * against the psychology scoring matrix.
 *
 * IMMUTABILITY RULE: a question id's option KEYS, meaning and scoring are
 * frozen once released — the scoring matrix is keyed by question id and stored
 * answers are keyed by option key, so editing them in place silently
 * re-scores every existing answer. Changing what a question asks or offers
 * means a NEW question id (and a new matrix entry), or a new quiz id. Only
 * wording (labels, messages) may change in place.
 */
export const QUESTIONS: QuestionDefinition[] = [
  {
    id: 'nenjam-mc-q01-v1',
    dimension: 'conflict_style',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText:
      "You and your partner disagree about something that matters to you. What's your natural first move?",
    options: [
      {
        key: 'A',
        label:
          'I want to talk it through right away, until we reach a resolution',
        value: 1,
      },
      {
        key: 'B',
        label: 'I need some time alone to process before I can discuss it calmly',
        value: 2,
      },
      { key: 'C', label: 'I look for a quick middle ground so we can move on', value: 3 },
      { key: 'D', label: 'I usually let my partner take the lead on resolving it', value: 4 },
    ],
    pairRules: [
      {
        pair: ['A', 'B'],
        type: 'flag',
        severity: 'soft',
        message: 'Agree on a pause-and-return rule for disagreements',
      },
      {
        pair: ['D', 'D'],
        type: 'flag',
        severity: 'soft',
        message: 'Decide who initiates tough conversations',
      },
    ],
    order: 1,
  },
  {
    id: 'nenjam-mc-q02-v1',
    dimension: 'financial_philosophy',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText: "How do you picture handling money once you're married?",
    options: [
      {
        key: 'A',
        label: 'Full transparency — joint accounts, joint decisions on everything, big or small',
        value: 1,
      },
      {
        key: 'B',
        label:
          'Joint accounts/goals for big things (house, savings), personal autonomy for day-to-day spending',
        value: 2,
      },
      {
        key: 'C',
        label: 'Mostly separate finances, with agreed contributions to shared expenses',
        value: 3,
      },
      {
        key: 'D',
        label: 'One of us should primarily manage and take the lead on household finances',
        value: 4,
      },
    ],
    pairRules: [
      {
        pair: ['A', 'C'],
        type: 'flag',
        severity: 'medium',
        message: 'Discuss money management before marriage, not after',
      },
      {
        pair: ['D', 'D'],
        type: 'flag',
        severity: 'soft',
        message: 'Clarify who owns financial decisions',
      },
    ],
    order: 2,
  },
  {
    id: 'nenjam-mc-q03-v1',
    dimension: 'family_boundaries',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText:
      "How involved do you want your (and your partner's) parents/extended family to be in your day-to-day married life and decisions?",
    options: [
      {
        key: 'A',
        label: 'Very involved — we consult them on most major decisions as a family unit',
        value: 1,
      },
      {
        key: 'B',
        label: 'Involved in major events and big decisions, but we decide our day-to-day independently',
        value: 2,
      },
      {
        key: 'C',
        label: 'Respectful distance — we keep them informed but make our own decisions',
        value: 3,
      },
      {
        key: 'D',
        label: 'Minimal — we prefer to keep our married life largely separate from extended family',
        value: 4,
      },
    ],
    pairRules: [
      {
        pair: ['A', 'D'],
        type: 'dealbreaker',
        severity: 'high',
        message:
          'This is a fundamental difference — involve both families in this conversation',
      },
      {
        pair: ['A', 'C'],
        type: 'flag',
        severity: 'medium',
        message: 'Align on how involved extended family should be',
      },
    ],
    order: 3,
  },
  {
    id: 'nenjam-mc-q04-v1',
    dimension: 'career_adaptability',
    scoringType: QuestionScoringType.COMPLEMENTARY_TOLERANT,
    questionText:
      "If one of your careers required relocating, long hours, or a big time investment for a few years, how do you picture your marriage adapting?",
    options: [
      {
        key: 'A',
        label: 'I expect my career to take priority at times, and my partner to be willing to adapt around it',
        value: 1,
      },
      {
        key: 'B',
        label: "We'd weigh it together each time and prioritize whichever opportunity benefits the family more",
        value: 2,
      },
      {
        key: 'C',
        label: "My career matters, but I'd want stability/location to take priority over big career swings",
        value: 3,
      },
      {
        key: 'D',
        label: 'I expect to scale back my career for family life if needed',
        value: 4,
      },
    ],
    pairRules: [
      {
        pair: ['A', 'A'],
        type: 'flag',
        severity: 'medium',
        message: "Discuss how you'll actually decide when careers compete",
      },
    ],
    order: 4,
  },
  {
    id: 'nenjam-mc-q05-v1',
    dimension: 'household_division',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText:
      "Picture you're both working full-time. How do you imagine dividing cooking, cleaning, finances, and other home responsibilities?",
    options: [
      { key: 'A', label: 'Strictly split down the middle — roughly 50/50 on everything', value: 1 },
      {
        key: 'B',
        label: 'Divided by whoever is better at or prefers each task, not by any fixed rule',
        value: 2,
      },
      {
        key: 'C',
        label: 'More traditional — one of us primarily runs the home, the other handles outside-the-home matters',
        value: 3,
      },
      {
        key: 'D',
        label: "We outsource/hire help where we can and split whatever's left",
        value: 4,
      },
    ],
    pairRules: [
      {
        pair: ['A', 'C'],
        type: 'flag',
        severity: 'medium',
        message: "Clarify what 'traditional' means to each of you",
      },
      {
        pair: ['C', 'C'],
        type: 'flag',
        severity: 'medium',
        message:
          "Clarify what 'traditional' means to each of you (ask a follow-up before treating C+C as automatically compatible)",
      },
    ],
    order: 5,
  },
  {
    id: 'nenjam-mc-q06-v1',
    dimension: 'emotional_support',
    scoringType: QuestionScoringType.COMPLEMENTARY_TOLERANT,
    questionText: "When you're stressed or upset, what helps you most from a partner?",
    options: [
      { key: 'A', label: 'Just listening, without trying to fix or advise', value: 1 },
      { key: 'B', label: 'Practical help — solutions, advice, a plan to fix the problem', value: 2 },
      { key: 'C', label: "Space alone first, then support once I've settled", value: 3 },
      { key: 'D', label: 'Physical closeness or quiet reassurance, more than words', value: 4 },
    ],
    pairRules: [
      {
        pair: ['A', 'B'],
        type: 'flag',
        severity: 'soft',
        message: 'Ask before you respond — do they want you to just listen, or help fix it?',
      },
      {
        pair: ['C', 'A'],
        type: 'flag',
        severity: 'soft',
        message: "Agree on a signal for 'give me a few minutes'",
      },
      {
        pair: ['C', 'B'],
        type: 'flag',
        severity: 'soft',
        message: "Agree on a signal for 'give me a few minutes'",
      },
      {
        pair: ['C', 'D'],
        type: 'flag',
        severity: 'soft',
        message: "Agree on a signal for 'give me a few minutes'",
      },
    ],
    order: 6,
  },
  {
    id: 'nenjam-mc-q07-v1',
    dimension: 'personal_space',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText:
      "How much independent time — own friends, hobbies, time alone — do you want to keep once you're married?",
    options: [
      { key: 'A', label: 'A lot — I value my own interests and independent time strongly', value: 1 },
      { key: 'B', label: 'A healthy balance of together-time and me-time', value: 2 },
      { key: 'C', label: 'I’d prefer we spend most of our time and activities together', value: 3 },
      { key: 'D', label: "It depends on the season of life / how I'm feeling", value: 4 },
    ],
    pairRules: [
      {
        pair: ['A', 'C'],
        type: 'flag',
        severity: 'medium',
        message: "You have very different needs for space — discuss what 'enough together time' looks like",
      },
      {
        pair: ['A', 'A'],
        type: 'flag',
        severity: 'soft',
        message: 'Informational: two independent lives can drift apart — worth a lighter-touch discussion',
      },
      {
        pair: ['C', 'C'],
        type: 'flag',
        severity: 'soft',
        message: 'Informational: shared-everything can tip into an enmeshed dynamic — worth a lighter-touch discussion',
      },
    ],
    order: 7,
  },
  {
    id: 'nenjam-mc-q08-v1',
    dimension: 'decision_making',
    scoringType: QuestionScoringType.COMPLEMENTARY_TOLERANT,
    questionText:
      "For a major life decision (buying a home, having a child, changing cities), what's your ideal process?",
    options: [
      { key: 'A', label: 'We each share our view, then decide together as equals', value: 1 },
      { key: 'B', label: "I prefer to lead and make the final call after hearing my partner's input", value: 2 },
      { key: 'C', label: "I'm comfortable letting my partner lead and supporting their decision", value: 3 },
      { key: 'D', label: 'We should involve our families before deciding', value: 4 },
    ],
    pairRules: [
      {
        pair: ['B', 'B'],
        type: 'flag',
        severity: 'medium',
        message: "You both expect to lead major decisions — decide how you'll handle disagreement",
      },
    ],
    order: 8,
  },
  {
    id: 'nenjam-mc-q09-v1',
    dimension: 'children',
    scoringType: QuestionScoringType.HARD_AXIS,
    questionText: 'What best describes where you stand on having children?',
    options: [
      { key: 'A', label: 'I want children fairly soon, with both partners actively co-parenting', value: 1 },
      { key: 'B', label: 'I want children, and expect a more traditional division of parenting roles', value: 2 },
      { key: 'C', label: "I'm open either way — I'd want to decide together over time", value: 3 },
      { key: 'D', label: "I don't want children, or want to decide on this much later", value: 4 },
    ],
    pairRules: [
      {
        pair: ['A', 'D'],
        type: 'dealbreaker',
        severity: 'hard',
        message: 'You and this match have different expectations about having children',
      },
      {
        pair: ['B', 'D'],
        type: 'dealbreaker',
        severity: 'hard',
        message: 'You and this match have different expectations about having children',
      },
      {
        pair: ['C', 'A'],
        type: 'flag',
        severity: 'soft',
        message: 'Set a timeline for this conversation',
      },
      {
        pair: ['C', 'B'],
        type: 'flag',
        severity: 'soft',
        message: 'Set a timeline for this conversation',
      },
      {
        pair: ['C', 'D'],
        type: 'flag',
        severity: 'soft',
        message: 'Set a timeline for this conversation',
      },
    ],
    order: 9,
  },
  {
    id: 'nenjam-mc-q10-v1',
    dimension: 'life_stage_timeline',
    scoringType: QuestionScoringType.MUST_ALIGN,
    questionText: 'How do you picture the first few years after marriage?',
    options: [
      { key: 'A', label: 'Settling into a stable home and routine fairly quickly', value: 1 },
      { key: 'B', label: 'Continuing to build career or personal goals before settling into a fixed routine', value: 2 },
      { key: 'C', label: 'Traveling and experiencing life together before taking on major responsibilities', value: 3 },
      { key: 'D', label: 'Focusing on starting a family soon', value: 4 },
    ],
    pairRules: [
      {
        pair: ['B', 'D'],
        type: 'flag',
        severity: 'medium',
        message: 'You agree on wanting a family, but may be picturing different timelines — worth aligning on sequencing (cross-check with the children question)',
      },
      {
        pair: ['C', 'D'],
        type: 'flag',
        severity: 'medium',
        message: 'You agree on wanting a family, but may be picturing different timelines — worth aligning on sequencing (cross-check with the children question)',
      },
    ],
    order: 10,
  },
];

/**
 * Seeds the psychology_quizzes and quiz_questions tables with the Marriage
 * Compatibility Quiz (10 scenario-based questions). This is the sole
 * questionnaire — the retired 20-question OCEAN quiz's rows are removed by
 * migration, not by this seeder (a seeder should never delete content; see
 * the marriage_psychology_questionnaire migration).
 * Safe to re-run: uses upsert so existing data is not duplicated.
 *
 * Re-running never changes whether the quiz is active: `isActive` is set only
 * when the quiz is first created. An operator who retires it (or activates a
 * newer quiz in its place) must not have that undone by the next seed.
 */
export async function seedQuiz(prisma: PrismaClient): Promise<void> {
  console.log('\n💑  Seeding Marriage Compatibility quiz…');

  const quiz = await prisma.psychologyQuiz.upsert({
    where: { id: QUIZ_ID },
    update: {
      title: 'Marriage Compatibility Quiz',
      description:
        '10 scenario-based questions covering the dimensions most predictive of marital strain: ' +
        'conflict resolution, money, family/in-law boundaries, career and role expectations, ' +
        'household division, emotional support, personal space, decision-making, children, and ' +
        'life-stage timeline. Answers are scored pairwise against a match, not individually.',
      version: '1.0',
    },
    create: {
      id: QUIZ_ID,
      title: 'Marriage Compatibility Quiz',
      description:
        '10 scenario-based questions covering the dimensions most predictive of marital strain: ' +
        'conflict resolution, money, family/in-law boundaries, career and role expectations, ' +
        'household division, emotional support, personal space, decision-making, children, and ' +
        'life-stage timeline. Answers are scored pairwise against a match, not individually.',
      version: '1.0',
      isActive: true,
    },
  });

  console.log(
    `  ✅  Quiz upserted: "${quiz.title}" v${quiz.version}  [id: ${quiz.id}, active: ${quiz.isActive}]`,
  );

  // Two active quizzes is a content-ops mistake, not a state the app is built
  // for (Discover and quiz submission both take "the" active quiz). Report it
  // loudly; never resolve it here — which one should stay active is the
  // operator's call, and a seeder must not deactivate content.
  const activeCount = await prisma.psychologyQuiz.count({
    where: { isActive: true },
  });
  if (activeCount > 1) {
    console.warn(
      `  ⚠️   ${activeCount} psychology quizzes are active. The most recently created one is used; deactivate the others.`,
    );
  }

  let upsertCount = 0;
  for (const q of QUESTIONS) {
    await prisma.quizQuestion.upsert({
      where: { id: q.id },
      // The literal-typed OptionDefinition/PairRuleDefinition[] (kept strict
      // for readability above) doesn't structurally overlap with Prisma's
      // InputJsonValue, hence the through-unknown cast — same value, just a
      // wider type at the Prisma call boundary.
      update: {
        dimension: q.dimension,
        scoringType: q.scoringType,
        questionText: q.questionText,
        options: q.options as unknown as Prisma.InputJsonValue,
        pairRules: q.pairRules as unknown as Prisma.InputJsonValue,
        order: q.order,
      },
      create: {
        id: q.id,
        quizId: quiz.id,
        dimension: q.dimension,
        scoringType: q.scoringType,
        questionText: q.questionText,
        options: q.options as unknown as Prisma.InputJsonValue,
        pairRules: q.pairRules as unknown as Prisma.InputJsonValue,
        order: q.order,
      },
    });
    upsertCount++;
  }

  console.log(`  ✅  ${upsertCount} quiz questions seeded successfully.`);
}
