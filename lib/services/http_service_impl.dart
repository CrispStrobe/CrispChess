/// Native HTTP implementation using dart:io.
import 'dart:convert';
import 'dart:io';

Future<String?> platformHttpGet(String url) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  }
}
