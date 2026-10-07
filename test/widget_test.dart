import 'package:flutter_test/flutter_test.dart';

import 'package:oregonetservice/push_notifications.dart';
import 'package:oregonetservice/whatsapp_link.dart';

void main() {
  test('isWhatsAppLink detects WhatsApp hosts', () {
    expect(isWhatsAppLink(Uri.parse('https://wa.me/628123')), isTrue);
    expect(isWhatsAppLink(Uri.parse('whatsapp://send?text=hi')), isTrue);
    expect(isWhatsAppLink(Uri.parse('https://api.whatsapp.com/send')), isTrue);
    expect(isWhatsAppLink(Uri.parse('https://google.com')), isFalse);
  });

  test('resolveAppPath only accepts same-host paths', () {
    final home = Uri.parse('https://oregonetservice.my.id/');
    expect(resolveAppPath('/worker/tasks/12', home)?.path, '/worker/tasks/12');
    expect(resolveAppPath('//evil.com/x', home), isNull);
    expect(resolveAppPath('https://evil.com/x', home), isNull);
  });
}
