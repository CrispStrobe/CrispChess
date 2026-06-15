/// Web HTTP implementation using JS fetch API.
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String?> platformHttpGet(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (response.status != 200) return null;
    final jsText = await response.text().toDart;
    return jsText.toDart;
  } catch (_) {
    return null;
  }
}
