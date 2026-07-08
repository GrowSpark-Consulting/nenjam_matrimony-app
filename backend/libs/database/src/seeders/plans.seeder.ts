import { PrismaClient } from '../../generated/client';

/**
 * Seeds the subscription_plans table with Silver and Gold plans.
 *
 * Pricing convention: stored in **paise** (₹1 = 100 paise) to match
 * Razorpay's integer-paise convention and avoid floating-point drift.
 *
 *   Silver → ₹499  → 49900 paise  / 30 days
 *   Gold   → ₹999  → 99900 paise  / 90 days
 */
export async function seedPlans(prisma: PrismaClient): Promise<void> {
  const plans = [
    {
      name: 'SILVER' as const,
      displayName: 'Silver Plan',
      priceInr: 49_900, // ₹499 in paise
      durationDays: 30,
      features: [
        'View up to 10 contact numbers per month',
        'Send up to 5 Express Interests per day',
        'Upload up to 4 profile photos',
        'See verified badge status of profiles',
        'Basic search filters (age, religion, city)',
        'Email & chat support',
      ],
      limits: {
        contactsPerMonth: 10,
        expressInterestsPerDay: 5,
        photoUploads: 4,
        aiCompatibilityReports: 0,
        priorityDiscovery: false,
        dedicatedManager: false,
      },
      isActive: true,
    },
    {
      name: 'GOLD' as const,
      displayName: 'Gold Plan',
      priceInr: 99_900, // ₹999 in paise
      durationDays: 90,
      features: [
        'Unlimited contact number views',
        'Unlimited Express Interests per day',
        'Upload up to 10 profile photos',
        'AI Compatibility Score for every match',
        'Horoscope Porutham match report (10-point)',
        'Priority placement in daily discovery feed',
        'See who shortlisted your profile',
        'Dedicated Royal Relationship Manager',
        'Priority email, chat & phone support',
      ],
      limits: {
        contactsPerMonth: -1, // -1 = unlimited
        expressInterestsPerDay: -1,
        photoUploads: 10,
        aiCompatibilityReports: -1,
        priorityDiscovery: true,
        dedicatedManager: true,
      },
      isActive: true,
    },
  ];

  console.log('\n📦  Seeding subscription plans…');

  for (const plan of plans) {
    const result = await prisma.subscriptionPlan.upsert({
      where: { name: plan.name },
      update: {
        displayName: plan.displayName,
        priceInr: plan.priceInr,
        durationDays: plan.durationDays,
        features: plan.features,
        limits: plan.limits,
        isActive: plan.isActive,
      },
      create: plan,
    });

    const priceRupees = (plan.priceInr / 100).toFixed(2);
    console.log(
      `  ✅  ${result.name} — ₹${priceRupees} / ${plan.durationDays} days  [id: ${result.id}]`,
    );
  }

  console.log('  Subscription plans seeded successfully.');
}
