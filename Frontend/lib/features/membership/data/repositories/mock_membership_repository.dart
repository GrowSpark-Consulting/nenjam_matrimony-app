import '../../../../core/network/api_exception.dart';
import '../../domain/models/checkout_models.dart';
import '../../domain/models/membership_models.dart';
import '../../domain/repositories/membership_repository.dart';

/// In-memory stand-in for tests and offline UI work. It mirrors the backend
/// as it is TODAY, using only values from the contract's own examples:
///
///  - three plans, every one with empty `durations` (no prices are set);
///  - `checkoutAvailable: false`;
///  - a Free member with the pre-membership photo cap of 6 and
///    `limitsEnforced: false` (shadow mode);
///  - no history, and checkout answering as unconfigured (503).
///
/// It never invents prices or plan benefits. Swap it in with
/// `membershipRepositoryProvider.overrideWithValue(MockMembershipRepository())`.
class MockMembershipRepository implements MembershipRepository {
  MockMembershipRepository({
    MembershipCatalog? catalog,
    MyMembership? me,
    List<MembershipHistoryItem>? history,
  }) : _catalog = catalog,
       _me = me,
       _history = history;

  final MembershipCatalog? _catalog;
  final MyMembership? _me;
  final List<MembershipHistoryItem>? _history;

  static final Map<String, dynamic> plansJson = {
    'checkoutAvailable': false,
    'plans': [
      {
        'code': 'FREE',
        'name': 'Free',
        'tier': 0,
        'isFree': true,
        'version': 1,
        'durations': <Object>[],
        'entitlements': {
          'interests.send': {'limit': 5},
          'chat.initiate': false,
          'search.verified_only': true,
          'support.tier': 'STANDARD',
        },
      },
      {
        'code': 'GOLD',
        'name': 'Gold',
        'tier': 1,
        'isFree': false,
        'version': 1,
        'durations': <Object>[],
      },
      {
        'code': 'PLATINUM',
        'name': 'Platinum',
        'tier': 2,
        'isFree': false,
        'version': 1,
        'durations': <Object>[],
      },
    ],
    'features': [
      {
        'key': 'interests.send',
        'kind': 'quota',
        'section': 'INTERESTS',
        'label': 'Sending interests',
        'period': 'MONTH',
      },
      {
        'key': 'support.tier',
        'kind': 'level',
        'section': 'SUPPORT',
        'label': 'Customer support',
        'levels': ['STANDARD', 'PRIORITY', 'DEDICATED'],
      },
      {
        'key': 'search.verified_only',
        'kind': 'boolean',
        'section': 'VERIFICATION',
        'label': 'Browsing verified profiles only',
        'requiredOnEveryPlan': true,
      },
    ],
  };

  static final Map<String, dynamic> freeMeJson = {
    'plan': {'code': 'FREE', 'name': 'Free', 'tier': 0},
    'source': 'FREE',
    'planVersion': 1,
    'subscription': null,
    'scheduled': <Object>[],
    'entitlements': (plansJson['plans'] as List).first['entitlements'],
    'usage': <Object>[],
    'purchaseOptions': <Object>[],
    'effectiveCaps': {
      'profile.photos': 6,
      'shortlist.profiles': null,
      'search.saved_searches': null,
      'insights.profile_viewers_visible': null,
    },
    'checkoutAvailable': false,
    'limitsEnforced': false,
  };

  @override
  Future<MembershipCatalog> getPlans() async =>
      _catalog ?? MembershipCatalog.fromJson(plansJson);

  @override
  Future<MyMembership> getMe() async =>
      _me ?? MyMembership.fromJson(freeMeJson);

  @override
  Future<List<MembershipHistoryItem>> getHistory() async =>
      _history ?? const [];

  @override
  Future<CheckoutSession> startCheckout(CheckoutRequest request) async =>
      throw ApiException(503, 'Payments are not configured.');

  @override
  Future<CheckoutVerifyResult> verifyCheckout(
    CheckoutVerifyRequest request,
  ) async => throw ApiException(503, 'Payments are not configured.');
}
