import 'package:url_launcher/url_launcher.dart';

/// `https://wa.me/?text=<message>` — WhatsApp's own share link, so no
/// WhatsApp API and no new share package (the app already has
/// `url_launcher`; it has no share-sheet plugin).
///
/// [message] is passed through untouched apart from URL-encoding: it is the
/// backend's finished text and is never rebuilt or reformatted here.
Uri whatsAppShareUri(String message) =>
    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');

/// Opens a URL outside the app; injectable so tests need no platform.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openExternalUrl(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens WhatsApp (or the browser's wa.me page) with [message]. Returns
/// false — never throws — when the message is empty or nothing opened.
Future<bool> shareOnWhatsApp(
  String message, {
  UrlOpener open = openExternalUrl,
}) async {
  if (message.trim().isEmpty) return false;
  try {
    return await open(whatsAppShareUri(message));
  } catch (_) {
    return false;
  }
}
