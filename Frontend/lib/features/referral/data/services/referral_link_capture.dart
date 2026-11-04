import 'link_referral_store.dart';

/// Longest `ref` value we will carry. A real code is 8 characters; the slack
/// covers spaces/hyphens a person may have typed into a shared link.
const int _maxRefLength = 32;

final RegExp _saneRef = RegExp(r'^[A-Za-z0-9 \-]+$');

/// Picks the referral code out of a landing URL's query string
/// (`/?ref=NM7K2P9X`), or null.
///
/// Safe by construction: a missing, empty, over-long or oddly-charactered
/// value is ignored, and when `ref` appears more than once the FIRST value
/// wins (a later duplicate cannot replace it). The value is returned
/// trimmed but otherwise as received — whether it is a *valid* code is
/// decided by the same `normalizeReferralCode` + validate call the manual
/// box uses, so a malformed code gets the ordinary "not valid" message.
String? referralFromQuery(Map<String, List<String>> queryParametersAll) {
  final values = queryParametersAll['ref'];
  if (values == null || values.isEmpty) return null;
  final first = values.first.trim();
  if (first.isEmpty || first.length > _maxRefLength) return null;
  if (!_saneRef.hasMatch(first)) return null;
  return first;
}

/// Reads `?ref=` from the URL the app was opened with and parks it in
/// [store] for the signup step to pick up. Call once, before the router
/// redirects away from the landing URL. Never throws, never logs the code.
void captureReferralFromUrl(Uri landing, LinkReferralStore store) {
  try {
    final ref = referralFromQuery(landing.queryParametersAll);
    if (ref != null) store.write(ref);
  } catch (_) {}
}
