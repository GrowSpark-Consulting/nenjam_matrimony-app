import 'link_referral_store_stub.dart'
    if (dart.library.js_interop) 'link_referral_store_web.dart';

/// Holds the raw `?ref=` value from a shared link until the signup box has
/// handled it.
///
/// Per-tab `sessionStorage` on the web (survives a refresh and in-app
/// navigation, disappears with the tab; nothing is written to localStorage).
/// Elsewhere there is no landing URL to read, so it is memory only.
///
/// This is a staging area, not the source of truth: once the code has been
/// validated it moves to `PendingReferralStore`, which already survives the
/// rest of signup and is cleared on attach/sign-out.
abstract class LinkReferralStore {
  String? read();
  void write(String ref);
  void clear();
}

LinkReferralStore createLinkReferralStore() => platformLinkReferralStore();

/// Memory-only store (non-web builds and tests).
class MemoryLinkReferralStore implements LinkReferralStore {
  MemoryLinkReferralStore([this._value]);

  String? _value;

  @override
  String? read() => _value;

  @override
  void write(String ref) => _value = ref;

  @override
  void clear() => _value = null;
}
