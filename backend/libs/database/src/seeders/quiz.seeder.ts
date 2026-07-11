import { OceanDomain, PrismaClient } from '../../generated/client';

// ─────────────────────────────────────────────────────────────
// 20 OCEAN questionnaire items — 4 questions per trait (O C E A N)
// Scoring: 5-point Likert  1=Strongly Disagree … 5=Strongly Agree
// reverseScored=true items are flipped (6 - score) before averaging.
// ─────────────────────────────────────────────────────────────

interface QuestionDefinition {
  oceanDomain: OceanDomain;
  questionText: string;
  reverseScored: boolean;
  order: number;
}

const QUESTIONS: QuestionDefinition[] = [
  // ── O · Openness to Experience (questions 1-4) ────────────
  {
    oceanDomain: OceanDomain.O,
    questionText:
      'I enjoy exploring new ideas and unconventional ways of thinking.',
    reverseScored: false,
    order: 1,
  },
  {
    oceanDomain: OceanDomain.O,
    questionText: 'I am imaginative and love engaging in creative activities.',
    reverseScored: false,
    order: 2,
  },
  {
    oceanDomain: OceanDomain.O,
    questionText:
      'I prefer familiar routines over new and unpredictable experiences.',
    reverseScored: true,
    order: 3,
  },
  {
    oceanDomain: OceanDomain.O,
    questionText:
      'I am genuinely curious about many different topics and subjects.',
    reverseScored: false,
    order: 4,
  },

  // ── C · Conscientiousness (questions 5-8) ────────────────
  {
    oceanDomain: OceanDomain.C,
    questionText:
      'I keep my personal belongings and workspaces neat and organised.',
    reverseScored: false,
    order: 5,
  },
  {
    oceanDomain: OceanDomain.C,
    questionText: 'I complete tasks thoroughly, accurately, and on time.',
    reverseScored: false,
    order: 6,
  },
  {
    oceanDomain: OceanDomain.C,
    questionText:
      'I often find it difficult to stick to plans and commitments.',
    reverseScored: true,
    order: 7,
  },
  {
    oceanDomain: OceanDomain.C,
    questionText:
      'I set clear long-term goals and work diligently to achieve them.',
    reverseScored: false,
    order: 8,
  },

  // ── E · Extraversion (questions 9-12) ────────────────────
  {
    oceanDomain: OceanDomain.E,
    questionText:
      'I feel comfortable and energised around many different people.',
    reverseScored: false,
    order: 9,
  },
  {
    oceanDomain: OceanDomain.E,
    questionText:
      'I am talkative and enjoy striking up conversations with strangers.',
    reverseScored: false,
    order: 10,
  },
  {
    oceanDomain: OceanDomain.E,
    questionText:
      'I prefer spending quiet time alone rather than attending social events.',
    reverseScored: true,
    order: 11,
  },
  {
    oceanDomain: OceanDomain.E,
    questionText:
      'I find parties and large social gatherings exciting and energising.',
    reverseScored: false,
    order: 12,
  },

  // ── A · Agreeableness (questions 13-16) ──────────────────
  {
    oceanDomain: OceanDomain.A,
    questionText: "I genuinely care about others' feelings and well-being.",
    reverseScored: false,
    order: 13,
  },
  {
    oceanDomain: OceanDomain.A,
    questionText:
      'I try to avoid conflicts and work towards keeping the peace.',
    reverseScored: false,
    order: 14,
  },
  {
    oceanDomain: OceanDomain.A,
    questionText:
      'I can be critical, argumentative, or harsh towards others at times.',
    reverseScored: true,
    order: 15,
  },
  {
    oceanDomain: OceanDomain.A,
    questionText:
      'I am willing to compromise my own interests to help others succeed.',
    reverseScored: false,
    order: 16,
  },

  // ── N · Neuroticism (questions 17-20) ────────────────────
  {
    oceanDomain: OceanDomain.N,
    questionText:
      'I often feel anxious or worried even without a clear reason.',
    reverseScored: false,
    order: 17,
  },
  {
    oceanDomain: OceanDomain.N,
    questionText: 'My mood changes frequently throughout the day.',
    reverseScored: false,
    order: 18,
  },
  {
    oceanDomain: OceanDomain.N,
    questionText:
      'I remain calm and emotionally stable when facing stressful situations.',
    reverseScored: true,
    order: 19,
  },
  {
    oceanDomain: OceanDomain.N,
    questionText:
      'I rarely experience intense feelings of sadness, worry, or irritability.',
    reverseScored: true,
    order: 20,
  },
];

/**
 * Seeds the psychology_quizzes and quiz_questions tables.
 * Creates the OCEAN Personality Profile v1 quiz with 20 items.
 * Safe to re-run: uses upsert so existing data is not duplicated.
 */
export async function seedQuiz(prisma: PrismaClient): Promise<void> {
  console.log('\n🧠  Seeding OCEAN psychology quiz…');

  // Upsert the quiz definition
  const quiz = await prisma.psychologyQuiz.upsert({
    where: { id: 'ocean-quiz-v1-seed' },
    update: {
      title: 'OCEAN Personality Profile',
      description:
        'A 20-question psychometric assessment based on the Big Five personality model ' +
        '(Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism). ' +
        'Results guide AI compatibility matching and partner recommendations.',
      version: '1.0',
      isActive: true,
    },
    create: {
      id: 'ocean-quiz-v1-seed',
      title: 'OCEAN Personality Profile',
      description:
        'A 20-question psychometric assessment based on the Big Five personality model ' +
        '(Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism). ' +
        'Results guide AI compatibility matching and partner recommendations.',
      version: '1.0',
      isActive: true,
    },
  });

  console.log(
    `  ✅  Quiz created: "${quiz.title}" v${quiz.version}  [id: ${quiz.id}]`,
  );

  // Upsert each question by its deterministic id
  let upsertCount = 0;
  for (const q of QUESTIONS) {
    const questionId = `ocean-q${String(q.order).padStart(2, '0')}-v1-seed`;

    await prisma.quizQuestion.upsert({
      where: { id: questionId },
      update: {
        oceanDomain: q.oceanDomain,
        questionText: q.questionText,
        reverseScored: q.reverseScored,
        order: q.order,
      },
      create: {
        id: questionId,
        quizId: quiz.id,
        oceanDomain: q.oceanDomain,
        questionText: q.questionText,
        reverseScored: q.reverseScored,
        order: q.order,
      },
    });
    upsertCount++;
  }

  // Log trait breakdown
  const domains: OceanDomain[] = [
    OceanDomain.O,
    OceanDomain.C,
    OceanDomain.E,
    OceanDomain.A,
    OceanDomain.N,
  ];
  const traitNames: Record<OceanDomain, string> = {
    O: 'Openness        ',
    C: 'Conscientiousness',
    E: 'Extraversion    ',
    A: 'Agreeableness   ',
    N: 'Neuroticism     ',
  };
  for (const domain of domains) {
    const count = QUESTIONS.filter((q) => q.oceanDomain === domain).length;
    console.log(`  📊  ${traitNames[domain]} — ${count} questions`);
  }

  console.log(`  ✅  ${upsertCount} quiz questions seeded successfully.`);
}
