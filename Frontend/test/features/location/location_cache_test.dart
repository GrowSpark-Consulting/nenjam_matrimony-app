import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/location/data/location_cache.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The **real** [LocationCache], against a real SharedPreferences backend.
///
/// location_repository_test.dart already pins the cache-first *policy*, but it
/// does so with an in-memory fake — so every serialization, key and TTL
/// question in the actual implementation was untested. That is exactly where a
/// silent cache miss would hide: the repository would look correct, the tests
/// would pass, and every member would still pay a network round trip for a
/// country list they already had.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const cache = LocationCache();

  List<LocationOption> cities(int count) => [
        for (var i = 0; i < count; i++)
          LocationOption(
            code: 'IN-MH-CITY$i',
            label: 'City $i',
            parentCode: 'IN-MH',
          ),
      ];

  group('round trip', () {
    test('a written entry reads back', () async {
      const written = [
        LocationOption(code: 'IN', label: 'India'),
        LocationOption(code: 'CA', label: 'Canada'),
      ];

      await cache.write(LocationCache.countriesKey(), written);
      final read = await cache.read(LocationCache.countriesKey());

      expect(read, isNotNull, reason: 'a fresh write must read back');
      expect(read!.map((o) => o.code), ['IN', 'CA']);
      expect(read.map((o) => o.label), ['India', 'Canada']);
    });

    test('preserves the parent code, which scopes every child lookup', () async {
      const written = [
        LocationOption(
          code: 'IN-GJ-BHAVNAGAR',
          label: 'Bhavnagar',
          parentCode: 'IN-GJ',
        ),
      ];

      await cache.write(LocationCache.citiesKey('IN-GJ'), written);
      final read = await cache.read(LocationCache.citiesKey('IN-GJ'));

      expect(read!.single.parentCode, 'IN-GJ');
    });

    test('preserves the subdivision type, which the picker displays', () async {
      const written = [
        LocationOption(
          code: 'IN-GJ',
          label: 'Gujarat',
          parentCode: 'IN',
          type: 'State',
        ),
      ];

      await cache.write(LocationCache.statesKey('IN'), written);
      expect((await cache.read(LocationCache.statesKey('IN')))!.single.type,
          'State');
    });

    test('each parent is cached under its own key', () async {
      await cache.write(LocationCache.citiesKey('IN-GJ'), cities(2));
      await cache.write(LocationCache.citiesKey('IN-MH'), cities(5));

      expect((await cache.read(LocationCache.citiesKey('IN-GJ')))!.length, 2);
      expect((await cache.read(LocationCache.citiesKey('IN-MH')))!.length, 5);
      // A state never written must miss rather than borrow a sibling's list.
      expect(await cache.read(LocationCache.citiesKey('IN-TN')), isNull);
    });

    test('a full-size city list survives the round trip intact', () async {
      // Maharashtra is one of the larger subdivisions; the repository asks for
      // up to 1000 per state, so this is the realistic upper bound.
      final written = cities(800);
      await cache.write(LocationCache.citiesKey('IN-MH'), written);
      final read = await cache.read(LocationCache.citiesKey('IN-MH'));

      expect(read!.length, 800);
      expect(read.first.code, 'IN-MH-CITY0');
      expect(read.last.code, 'IN-MH-CITY799');
    });
  });

  group('misses', () {
    test('an unwritten key misses', () async {
      expect(await cache.read(LocationCache.countriesKey()), isNull);
    });

    test('an entry past its TTL misses and is dropped', () async {
      // Written eight days ago — one past the seven-day TTL.
      final stale = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        LocationCache.countriesKey(): jsonEncode({
          'at': stale,
          'items': [
            {'code': 'IN', 'label': 'India'},
          ],
        }),
        'location_cache_schema_version': 1,
      });

      expect(await cache.read(LocationCache.countriesKey()), isNull);
    });

    test('an entry inside its TTL hits', () async {
      final recent = DateTime.now()
          .subtract(const Duration(days: 6))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        LocationCache.countriesKey(): jsonEncode({
          'at': recent,
          'items': [
            {'code': 'IN', 'label': 'India'},
          ],
        }),
        'location_cache_schema_version': 1,
      });

      expect((await cache.read(LocationCache.countriesKey()))!.single.code, 'IN');
    });

    test('corrupt JSON misses rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        LocationCache.countriesKey(): 'not json at all',
        'location_cache_schema_version': 1,
      });

      // A cache is an optimisation; an unreadable one means "fetch again",
      // never an error the member sees.
      expect(await cache.read(LocationCache.countriesKey()), isNull);
    });

    test('an entry from an older schema version is discarded', () async {
      SharedPreferences.setMockInitialValues({
        LocationCache.countriesKey(): jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'items': [
            {'code': 'IN', 'label': 'India'},
          ],
        }),
        'location_cache_schema_version': 0,
      });

      expect(await cache.read(LocationCache.countriesKey()), isNull);
    });
  });

  group('the second read is the one that matters', () {
    test('write then read then read again all hit', () async {
      await cache.write(LocationCache.statesKey('IN'), cities(38));

      // Three consecutive reads, as three screen opens would do.
      for (var i = 0; i < 3; i++) {
        final read = await cache.read(LocationCache.statesKey('IN'));
        expect(read, isNotNull, reason: 'read ${i + 1} missed');
        expect(read!.length, 38);
      }
    });

    test('a miss does not poison the next write', () async {
      expect(await cache.read(LocationCache.citiesKey('IN-MH')), isNull);
      await cache.write(LocationCache.citiesKey('IN-MH'), cities(3));
      expect((await cache.read(LocationCache.citiesKey('IN-MH')))!.length, 3);
    });
  });
}
