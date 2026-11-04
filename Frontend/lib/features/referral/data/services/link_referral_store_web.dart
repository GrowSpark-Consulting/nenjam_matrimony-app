import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'link_referral_store.dart';

const String _key = 'nm_pending_link_ref';

LinkReferralStore platformLinkReferralStore() => _SessionStorageLinkStore();

/// `window.sessionStorage`, with every failure (storage disabled, private
/// mode, quota) reading as "nothing there" — a referral link must never be
/// the reason signup breaks.
class _SessionStorageLinkStore implements LinkReferralStore {
  JSObject? get _storage {
    try {
      final s = globalContext.getProperty<JSAny?>('sessionStorage'.toJS);
      return s as JSObject?;
    } catch (_) {
      return null;
    }
  }

  @override
  String? read() {
    try {
      final v = _storage?.callMethod<JSAny?>('getItem'.toJS, _key.toJS);
      final s = (v as JSString?)?.toDart;
      return (s == null || s.isEmpty) ? null : s;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String ref) {
    try {
      _storage?.callMethod<JSAny?>('setItem'.toJS, _key.toJS, ref.toJS);
    } catch (_) {}
  }

  @override
  void clear() {
    try {
      _storage?.callMethod<JSAny?>('removeItem'.toJS, _key.toJS);
    } catch (_) {}
  }
}
