import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/profile/presentation/utils/profile_dashboard_mapper.dart';

/// The profile ID chip shows a *shortened* uid but must copy the *whole* one.
///
/// Truncation is deliberate and purely visual — 8 characters is what fits the
/// chip and the hero card. The bug these tests pin is the clipboard path:
/// tapping the chip used to copy that same 8-character prefix, which support
/// cannot resolve to an account and which is not guaranteed unique across
/// users. Display stays short; the copy carries the full uid.
void main() {
  // A realistic Firebase uid: 28 chars, mixed case.
  const fullUid = 'A1b2C3d4e5F6g7H8i9J0k1L2m3N4';

  group('profileDisplayId — display stays truncated', () {
    test('shortens a full Firebase uid to 8 upper-case characters', () {
      const user = AuthUser(uid: fullUid);

      expect(profileDisplayId(user), 'A1B2C3D4');
      expect(profileDisplayId(user).length, 8);
    });

    test('leaves a uid of 8 or fewer characters intact, upper-cased', () {
      expect(profileDisplayId(const AuthUser(uid: 'abc123')), 'ABC123');
      expect(profileDisplayId(const AuthUser(uid: 'abcd1234')), 'ABCD1234');
    });

    test('renders a placeholder when there is no signed-in user', () {
      expect(profileDisplayId(null), '—');
      expect(profileDisplayId(const AuthUser(uid: '')), '—');
    });

    test('collides for uids sharing a prefix — why it must not be an ID', () {
      const a = AuthUser(uid: '${fullUid}aaaa');
      const b = AuthUser(uid: '${fullUid}bbbb');

      // Two distinct accounts, one identical display value. This is exactly
      // why the copied value has to be the full uid.
      expect(profileDisplayId(a), profileDisplayId(b));
      expect(profileCopyId(a), isNot(profileCopyId(b)));
    });
  });

  group('profileCopyId — clipboard carries the complete uid', () {
    test('returns the full uid, untruncated and case-preserved', () {
      expect(profileCopyId(const AuthUser(uid: fullUid)), fullUid);
      expect(profileCopyId(const AuthUser(uid: fullUid)).length, 28);
    });

    test('is empty when there is no signed-in user', () {
      expect(profileCopyId(null), '');
      expect(profileCopyId(const AuthUser(uid: '')), '');
    });

    test('differs from the displayed value for a real-length uid', () {
      const user = AuthUser(uid: fullUid);

      expect(profileCopyId(user), isNot(profileDisplayId(user)));
      expect(profileCopyId(user).startsWith(fullUid.substring(0, 8)), isTrue);
    });
  });

  group('ID chip clipboard wiring', () {
    /// Mirrors `_ProfileIdChip._copy`: prefer the full uid, fall back to the
    /// displayed value so the chip never copies an empty string.
    String copyTextFor(AuthUser? user) {
      final copyValue = profileCopyId(user);
      return copyValue.isNotEmpty ? copyValue : profileDisplayId(user);
    }

    testWidgets('places the full uid on the clipboard, not the short form', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await Clipboard.setData(
        ClipboardData(text: copyTextFor(const AuthUser(uid: fullUid))),
      );

      expect(copied.single, fullUid);
      expect(copied.single, isNot('A1B2C3D4'));
    });

    test('falls back to the displayed value when there is no uid', () {
      expect(copyTextFor(null), '—');
    });
  });
}
