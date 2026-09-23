import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks if the URI is a WhatsApp link (wa.me or whatsapp: scheme).
bool isWhatsAppLink(Uri uri) {
  if (uri.scheme == 'whatsapp') return true;
  if (uri.host == 'wa.me' || uri.host.endsWith('.wa.me')) return true;
  if (uri.host == 'api.whatsapp.com' || uri.host.endsWith('.api.whatsapp.com')) return true;
  if (uri.host == 'chat.whatsapp.com' || uri.host.endsWith('.chat.whatsapp.com')) return true;
  return false;
}

/// Opens the URI externally using the system's default handler.
Future<void> openExternally(Uri uri) async {
  final url = uri.toString();
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    // Fallback: copy to clipboard if launch fails
    await Clipboard.setData(ClipboardData(text: url));
  }
}