import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['SCREENSHOT_OUTPUT'] ?? 'appstore-shots',
  );
  final suffix = Platform.environment['SCREENSHOT_SUFFIX'] ?? 'device';
  output.createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final file = File('${output.path}/$screenshotName-$suffix.png');
      file.writeAsBytesSync(screenshotBytes);
      stdout.writeln('captured ${file.path} (${screenshotBytes.length} bytes)');
      return true;
    },
  );
}
