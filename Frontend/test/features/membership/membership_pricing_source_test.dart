import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';
import 'package:nenjam_matrimony/features/membership/presentation/providers/membership_providers.dart';

/// Prices belong to the backend (`GET /membership/plans`). These tests pin
/// that: a changed price shows on the next fetch, an unpriced length is never
/// purchasable, and no price literal exists in the app source.
void main() {
  MembershipCatalog catalog({int? price, bool checkout = true}) {
    final plans = (MockMembershipRepository.plansJson['plans'] as List)
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    plans[1]['durations'] = [
      {
        'months': 3,
        'durationDays': 90,
        'bonusDays': 0,
        'priceInPaise': price,
        'currency': 'INR',
      },
    ];
    return MembershipCatalog.fromJson({
      ...MockMembershipRepository.plansJson,
      'checkoutAvailable': checkout,
      'plans': plans,
    });
  }

  test('a changed backend price shows on the next plans fetch', () async {
    final repo = _MutableCatalogRepo(catalog(price: 399900));
    final container = ProviderContainer(
      overrides: [membershipRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    int? paid() => container
        .read(membershipPlansProvider)
        .requireValue
        .plans
        .firstWhere((p) => !p.isFree)
        .durations
        .single
        .priceInPaise;

    await container.read(membershipPlansProvider.future);
    expect(paid(), 399900);

    repo.next = catalog(price: 449900);
    container.invalidate(membershipPlansProvider);
    await container.read(membershipPlansProvider.future);
    expect(paid(), 449900);
    expect(repo.fetches, 2);
  });

  test('an unpriced length is not purchasable, even with checkout on', () {
    final c = catalog(price: null);
    expect(c.plans.where((p) => !p.isFree).expand((p) => p.priced), isEmpty);
    expect(c.hasPurchasablePlans, isFalse);
  });

  test('checkout off means nothing is purchasable, whatever is priced', () {
    final c = catalog(price: 399900, checkout: false);
    expect(c.hasPurchasablePlans, isFalse);
  });

  test('no price literal in the membership or premium source', () {
    // ₹ followed by a digit, or a priceInPaise assigned a number: both mean a
    // price typed into the app instead of read from the API.
    final literal = RegExp(r'₹\s?\d|priceInPaise\s*[:=]\s*\d');
    final offenders = <String>[];
    for (final dir in const [
      'lib/features/membership',
      'lib/features/premium',
    ]) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        // Comments may quote example amounts; only code can hold a price.
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (literal.hasMatch(code)) offenders.add(f.path);
      }
    }
    for (final arb in const ['lib/l10n/app_en.arb', 'lib/l10n/app_ta.arb']) {
      if (RegExp(r'₹\s?\d').hasMatch(File(arb).readAsStringSync())) {
        offenders.add(arb);
      }
    }
    expect(offenders, isEmpty);
  });
}

class _MutableCatalogRepo extends MockMembershipRepository {
  _MutableCatalogRepo(this.next);

  MembershipCatalog next;
  int fetches = 0;

  @override
  Future<MembershipCatalog> getPlans() async {
    fetches++;
    return next;
  }
}
