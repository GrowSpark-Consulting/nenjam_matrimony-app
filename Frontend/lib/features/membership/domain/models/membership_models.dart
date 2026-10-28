import '../../../../core/utils/server_time.dart';

/// Membership read models — `GET /membership/plans`, `/me` and `/history`.
///
/// Shapes follow docs/membership/api-contract.md exactly. Parsing is lenient
/// on purpose: an unknown feature id, `source`, `kind` or `status` is kept as
/// its raw string (or mapped to an `unknown` value) rather than thrown on, so
/// a backend that adds a value never breaks the app. Money is integer paise;
/// timestamps are parsed into local time.
///
/// The backend is the only authority on what a member has. Nothing here is
/// ever cached or set locally as proof of a plan.

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _stringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _intOrNull(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

bool _bool(Object? value) => value == true;

List<Map<String, dynamic>> _maps(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
];

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

// ─── GET /membership/plans ────────────────────────────────────────────────

/// One priced, on-sale length of a plan.
class MembershipDuration {
  const MembershipDuration({
    required this.months,
    required this.durationDays,
    required this.bonusDays,
    required this.priceInPaise,
    required this.currency,
  });

  factory MembershipDuration.fromJson(Map<String, dynamic> json) =>
      MembershipDuration(
        months: _intOrNull(json['months']) ?? 0,
        durationDays: _intOrNull(json['durationDays']) ?? 0,
        bonusDays: _intOrNull(json['bonusDays']) ?? 0,
        priceInPaise: _intOrNull(json['priceInPaise']),
        currency: _string(json['currency'], 'INR'),
      );

  final int months;
  final int durationDays;
  final int bonusDays;

  /// Null only if the backend ever lists an unpriced length; such a length
  /// is never shown as purchasable.
  final int? priceInPaise;
  final String currency;
}

class MembershipPlan {
  const MembershipPlan({
    required this.code,
    required this.name,
    required this.tier,
    required this.isFree,
    required this.durations,
    this.description,
    this.version,
    this.entitlements,
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) => MembershipPlan(
    code: _string(json['code']),
    name: _string(json['name']),
    description: _stringOrNull(json['description']),
    tier: _intOrNull(json['tier']) ?? 0,
    isFree: _bool(json['isFree']),
    version: _intOrNull(json['version']),
    durations: [
      for (final d in _maps(json['durations'])) MembershipDuration.fromJson(d),
    ],
    entitlements: _mapOrNull(json['entitlements']),
  );

  final String code;
  final String name;
  final String? description;
  final int tier;
  final bool isFree;
  final int? version;

  /// Only lengths priced and on sale. Empty while no prices are set.
  final List<MembershipDuration> durations;

  /// Raw entitlement values keyed by feature id — see [EntitlementValue].
  final Map<String, Object?>? entitlements;

  /// Durations that can actually be bought (a price is present).
  List<MembershipDuration> get priced =>
      durations.where((d) => d.priceInPaise != null).toList();
}

enum MembershipFeatureKind { boolean, level, quota, cap, unknown }

/// A feature definition from the catalogue — labels come from the API, so
/// the app never hard-codes a feature list.
class MembershipFeature {
  const MembershipFeature({
    required this.key,
    required this.kind,
    required this.label,
    this.section,
    this.period,
    this.levels = const [],
    this.requiredOnEveryPlan = false,
  });

  factory MembershipFeature.fromJson(Map<String, dynamic> json) {
    final kind = _string(json['kind']);
    return MembershipFeature(
      key: _string(json['key']),
      kind: MembershipFeatureKind.values.firstWhere(
        (k) => k.name == kind,
        orElse: () => MembershipFeatureKind.unknown,
      ),
      label: _string(json['label'], _string(json['key'])),
      section: _stringOrNull(json['section']),
      period: _stringOrNull(json['period']),
      levels: [
        if (json['levels'] is List)
          for (final l in json['levels'] as List)
            if (l is String) l,
      ],
      requiredOnEveryPlan: _bool(json['requiredOnEveryPlan']),
    );
  }

  final String key;
  final MembershipFeatureKind kind;
  final String label;
  final String? section;

  /// `DAY` / `MONTH` / … for a quota; null for a cap.
  final String? period;
  final List<String> levels;
  final bool requiredOnEveryPlan;
}

class MembershipCatalog {
  const MembershipCatalog({
    required this.checkoutAvailable,
    required this.plans,
    required this.features,
  });

  factory MembershipCatalog.fromJson(
    Map<String, dynamic> json,
  ) => MembershipCatalog(
    checkoutAvailable: _bool(json['checkoutAvailable']),
    plans: [for (final p in _maps(json['plans'])) MembershipPlan.fromJson(p)]
      ..sort((a, b) => a.tier.compareTo(b.tier)),
    features: [
      for (final f in _maps(json['features'])) MembershipFeature.fromJson(f),
    ],
  );

  final bool checkoutAvailable;
  final List<MembershipPlan> plans;
  final List<MembershipFeature> features;

  /// True when something can actually be bought: checkout is on and at least
  /// one paid plan has a priced length. Otherwise the app shows its honest
  /// "coming soon" state and no plans at all.
  bool get hasPurchasablePlans =>
      checkoutAvailable && plans.any((p) => !p.isFree && p.priced.isNotEmpty);
}

/// One entitlement value, in the three shapes the contract defines:
/// `bool`, a level string, or `{ limit: n | null, perMonths?, fairUse? }`.
class EntitlementValue {
  const EntitlementValue._({
    this.included,
    this.level,
    this.limit,
    this.unlimited = false,
    this.perMonths,
  });

  /// Returns null when [raw] has none of the contract's shapes.
  static EntitlementValue? parse(Object? raw) {
    if (raw is bool) return EntitlementValue._(included: raw);
    if (raw is String) return EntitlementValue._(level: raw);
    if (raw is Map && raw.containsKey('limit')) {
      final limit = raw['limit'];
      if (limit == null) return const EntitlementValue._(unlimited: true);
      final n = _intOrNull(limit);
      if (n == null) return null;
      return EntitlementValue._(
        limit: n,
        perMonths: _intOrNull(raw['perMonths']),
      );
    }
    return null;
  }

  final bool? included;
  final String? level;
  final int? limit;
  final bool unlimited;
  final int? perMonths;
}

// ─── GET /membership/me ───────────────────────────────────────────────────

enum MembershipSource { free, subscription, legacy, unavailable, unknown }

MembershipSource _source(Object? value) => switch (value) {
  'FREE' => MembershipSource.free,
  'SUBSCRIPTION' => MembershipSource.subscription,
  'LEGACY' => MembershipSource.legacy,
  'UNAVAILABLE' => MembershipSource.unavailable,
  _ => MembershipSource.unknown,
};

class MembershipPlanRef {
  const MembershipPlanRef({required this.code, required this.name, this.tier});

  factory MembershipPlanRef.fromJson(Map<String, dynamic> json) =>
      MembershipPlanRef(
        code: _string(json['code']),
        name: _string(json['name'], _string(json['code'])),
        tier: _intOrNull(json['tier']),
      );

  final String code;
  final String name;
  final int? tier;
}

class MembershipSubscription {
  const MembershipSubscription({
    required this.id,
    required this.planCode,
    required this.status,
    this.startDate,
    this.endDate,
    this.months,
  });

  factory MembershipSubscription.fromJson(Map<String, dynamic> json) =>
      MembershipSubscription(
        id: _string(json['id']),
        planCode: _string(json['planCode']),
        status: _string(json['status']),
        startDate: tryParseServerTime(json['startDate']),
        endDate: tryParseServerTime(json['endDate']),
        months: _intOrNull(json['months']),
      );

  final String id;
  final String planCode;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? months;
}

/// A plan already bought and queued to start later.
class ScheduledMembership {
  const ScheduledMembership({
    required this.id,
    required this.planCode,
    required this.planName,
    this.startDate,
    this.endDate,
  });

  factory ScheduledMembership.fromJson(Map<String, dynamic> json) =>
      ScheduledMembership(
        id: _string(json['id']),
        planCode: _string(json['planCode']),
        planName: _string(json['planName'], _string(json['planCode'])),
        startDate: tryParseServerTime(json['startDate']),
        endDate: tryParseServerTime(json['endDate']),
      );

  final String id;
  final String planCode;
  final String planName;
  final DateTime? startDate;
  final DateTime? endDate;
}

class MembershipUsage {
  const MembershipUsage({
    required this.feature,
    required this.used,
    this.period,
    this.limit,
    this.remaining,
    this.fairUse = false,
    this.resetsAt,
  });

  factory MembershipUsage.fromJson(Map<String, dynamic> json) =>
      MembershipUsage(
        feature: _string(json['feature']),
        period: _stringOrNull(json['period']),
        used: _intOrNull(json['used']) ?? 0,
        limit: _intOrNull(json['limit']),
        remaining: _intOrNull(json['remaining']),
        fairUse: _bool(json['fairUse']),
        resetsAt: tryParseServerTime(json['resetsAt']),
      );

  final String feature;
  final String? period;
  final int used;

  /// Null = unlimited.
  final int? limit;
  final int? remaining;
  final bool fairUse;
  final DateTime? resetsAt;
}

enum PurchaseKind { newPlan, upgrade, renewal, downgrade, unknown }

class PurchaseOption {
  const PurchaseOption({
    required this.planCode,
    required this.planName,
    required this.months,
    required this.priceInPaise,
    required this.currency,
    required this.kind,
    this.startsAt,
    this.endsAt,
  });

  factory PurchaseOption.fromJson(Map<String, dynamic> json) => PurchaseOption(
    planCode: _string(json['planCode']),
    planName: _string(json['planName'], _string(json['planCode'])),
    months: _intOrNull(json['months']) ?? 0,
    priceInPaise: _intOrNull(json['priceInPaise']),
    currency: _string(json['currency'], 'INR'),
    kind: switch (json['kind']) {
      'NEW' => PurchaseKind.newPlan,
      'UPGRADE' => PurchaseKind.upgrade,
      'RENEWAL' => PurchaseKind.renewal,
      'DOWNGRADE' => PurchaseKind.downgrade,
      _ => PurchaseKind.unknown,
    },
    startsAt: tryParseServerTime(json['startsAt']),
    endsAt: tryParseServerTime(json['endsAt']),
  );

  final String planCode;
  final String planName;
  final int months;
  final int? priceInPaise;
  final String currency;
  final PurchaseKind kind;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// `RENEWAL`/`DOWNGRADE` are queued to [startsAt]; the member is told so
  /// before paying.
  bool get isQueued =>
      kind == PurchaseKind.renewal || kind == PurchaseKind.downgrade;
}

class MyMembership {
  const MyMembership({
    required this.plan,
    required this.source,
    required this.scheduled,
    required this.usage,
    required this.purchaseOptions,
    required this.effectiveCaps,
    required this.checkoutAvailable,
    required this.limitsEnforced,
    this.planVersion,
    this.subscription,
    this.entitlements,
  });

  factory MyMembership.fromJson(Map<String, dynamic> json) {
    final caps = <String, int?>{};
    final rawCaps = json['effectiveCaps'];
    if (rawCaps is Map) {
      for (final entry in rawCaps.entries) {
        final key = entry.key;
        if (key is! String) continue;
        final value = entry.value;
        if (value == null) {
          caps[key] = null; // null = no cap
        } else {
          final n = _intOrNull(value);
          if (n != null && n >= 0) caps[key] = n;
        }
      }
    }
    final planJson = json['plan'];
    final subscription = json['subscription'];
    return MyMembership(
      plan: planJson is Map
          ? MembershipPlanRef.fromJson(Map<String, dynamic>.from(planJson))
          : const MembershipPlanRef(code: '', name: ''),
      source: _source(json['source']),
      planVersion: _intOrNull(json['planVersion']),
      subscription: subscription is Map
          ? MembershipSubscription.fromJson(
              Map<String, dynamic>.from(subscription),
            )
          : null,
      scheduled: [
        for (final s in _maps(json['scheduled']))
          ScheduledMembership.fromJson(s),
      ],
      entitlements: _mapOrNull(json['entitlements']),
      usage: [
        for (final u in _maps(json['usage'])) MembershipUsage.fromJson(u),
      ],
      purchaseOptions: [
        for (final p in _maps(json['purchaseOptions']))
          PurchaseOption.fromJson(p),
      ],
      effectiveCaps: caps,
      checkoutAvailable: _bool(json['checkoutAvailable']),
      limitsEnforced: _bool(json['limitsEnforced']),
    );
  }

  final MembershipPlanRef plan;
  final MembershipSource source;
  final int? planVersion;
  final MembershipSubscription? subscription;
  final List<ScheduledMembership> scheduled;

  /// Null for `LEGACY` and `UNAVAILABLE`.
  final Map<String, Object?>? entitlements;
  final List<MembershipUsage> usage;
  final List<PurchaseOption> purchaseOptions;

  /// What the server holds the member to right now. A present key with a
  /// null value means "no cap"; an absent key means the server didn't say.
  final Map<String, int?> effectiveCaps;
  final bool checkoutAvailable;
  final bool limitsEnforced;

  /// `LEGACY` and `UNAVAILABLE` never show limits or upgrade prompts.
  bool get mayShowUpgradePrompts =>
      source == MembershipSource.free ||
      source == MembershipSource.subscription;

  bool get hasPaidPlan =>
      source == MembershipSource.subscription ||
      source == MembershipSource.legacy;
}

// ─── GET /membership/history ──────────────────────────────────────────────

class MembershipPayment {
  const MembershipPayment({
    required this.id,
    required this.status,
    required this.currency,
    this.amountInPaise,
    this.paidAt,
    this.refundedAmount,
    this.refundedAt,
  });

  factory MembershipPayment.fromJson(Map<String, dynamic> json) =>
      MembershipPayment(
        id: _string(json['id']),
        status: _string(json['status']),
        amountInPaise: _intOrNull(json['amountInPaise']),
        currency: _string(json['currency'], 'INR'),
        paidAt: tryParseServerTime(json['paidAt']),
        refundedAmount: _intOrNull(json['refundedAmount']),
        refundedAt: tryParseServerTime(json['refundedAt']),
      );

  final String id;
  final String status;
  final int? amountInPaise;
  final String currency;
  final DateTime? paidAt;
  final int? refundedAmount;
  final DateTime? refundedAt;
}

class MembershipHistoryItem {
  const MembershipHistoryItem({
    required this.id,
    required this.plan,
    required this.status,
    required this.source,
    required this.currency,
    required this.payments,
    this.months,
    this.startDate,
    this.endDate,
    this.priceInPaise,
    this.cancellationReason,
    this.createdAt,
  });

  factory MembershipHistoryItem.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'];
    return MembershipHistoryItem(
      id: _string(json['id']),
      plan: plan is Map
          ? MembershipPlanRef.fromJson(Map<String, dynamic>.from(plan))
          : const MembershipPlanRef(code: '', name: ''),
      months: _intOrNull(json['months']),
      status: _string(json['status']),
      source: _string(json['source']),
      startDate: tryParseServerTime(json['startDate']),
      endDate: tryParseServerTime(json['endDate']),
      priceInPaise: _intOrNull(json['priceInPaise']),
      currency: _string(json['currency'], 'INR'),
      cancellationReason: _stringOrNull(json['cancellationReason']),
      createdAt: tryParseServerTime(json['createdAt']),
      payments: [
        for (final p in _maps(json['payments'])) MembershipPayment.fromJson(p),
      ],
    );
  }

  final String id;
  final MembershipPlanRef plan;
  final int? months;

  /// `PENDING`, `ACTIVE`, `EXPIRED`, `CANCELLED`, or a future value.
  final String status;

  /// `PURCHASE`, `ADMIN_GRANT`, or a future value.
  final String source;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? priceInPaise;
  final String currency;

  /// `REFUNDED` / `REVOKED` when [status] is `CANCELLED`.
  final String? cancellationReason;
  final DateTime? createdAt;
  final List<MembershipPayment> payments;
}
