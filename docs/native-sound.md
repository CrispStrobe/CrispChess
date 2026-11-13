# Native sound effects

`createSoundService()` keeps the existing synchronous `play`, `enabled`, `volume`
and `dispose` API. Native uses audioplayers 6.8.1 (MIT), a lazy single player and
eight local PCM WAV assets. Web still uses the existing conditional import,
Web Audio bridge and volume handling; no web sound code changed.

The localized settings toggle saves the sound preference and controls sound and haptics. Muting
stops active playback and invalidates pending effects, including assets loading
asynchronously. Newer events supersede pending events rather than accumulating
a delayed queue of chess sounds. Playback errors are caught asynchronously;
haptics are attempted independently for capture/check (medium) and illegal
(heavy), exactly as before. Disposal invalidates pending playback and releases
the player. Native volume now applies to samples (clamped by the base service).
Player and engine moves share event selection; SAN identifies captures, including en passant.

Android uses sonification with no audio-focus request, and iOS uses the ambient
category to mix with other audio and respect the silent switch. This avoids
intentionally interrupting spoken accessibility output. Existing visual and
semantic feedback remains in place. Audio-session interaction with voice moves,
VoiceOver/TalkBack, other apps and interruption/route changes still needs device
validation, especially because iOS shares one audio session between plugins.

## Platforms and prerequisites

The selected plugin declares Android, iOS, macOS, Linux and Windows support.
This is plugin support, not a claim that this change has run on those devices.
Flutter-generated Linux, Windows and macOS registrants include the new backend;
Android/iOS registration is managed by Flutter. Run `flutter pub get` and, on
Apple hosts, CocoaPods resolution before a native build; the existing Apple
Podfile locks have not been manually edited or validated with CocoaPods here.

- Flutter >=3.44 is required by this audioplayers release. The inspected SDK is
  Flutter 3.44.1 / Dart 3.12.1.
- Android: plugin minimum SDK 19; the app uses Flutter's higher default. Plugin
  requires Java 17 / compile SDK 36; the app uses Flutter compile SDK, AGP 8.11.1
  and Kotlin 2.2.20. Confirm the native build with the installed Android SDK/JDK.
- iOS: plugin minimum iOS 13, below the app's iOS 15 target.
- macOS: plugin and app minimum macOS 10.15.
- Linux: install GStreamer development packages, e.g. Debian/Ubuntu
  `libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`. Deployment also needs
  GStreamer runtime libraries, WAV parser/PCM decoder and a working audio sink
  (typically `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good` and the
  distribution's audio output plugin). These are system dependencies, not
  bundled by the Flutter plugin. GStreamer and its Good plug-ins are LGPL;
  review that external system dependency against the licensing rule in `PLAN.md`
  before merging. See [GStreamer modules](https://gstreamer.freedesktop.org/modules/).
- Windows: backend uses Media Foundation; its CMake build resolves Microsoft's
  Windows Implementation Library through NuGet. Validate on a Windows host with
  Flutter's desktop build prerequisites and Media Foundation available.

Sources: [package/platforms](https://pub.dev/packages/audioplayers),
[MIT license](https://pub.dev/packages/audioplayers/license),
[Linux setup](https://github.com/bluefireteam/audioplayers/tree/main/packages/audioplayers_linux).
The resolved package manifests/build definitions were also inspected locally.
Sample provenance and regeneration instructions are in
[`assets/sounds/README.md`](../assets/sounds/README.md).

## Automated validation

Focused command for a normal writable Flutter installation:

```sh
flutter test --no-pub test/sound_service_test.dart test/sound_service_native_test.dart test/move_sound_test.dart test/sound_settings_test.dart
flutter analyze --no-pub lib/services/sound_service.dart lib/services/sound_service_factory.dart lib/services/sound_service_native.dart test/sound_service_test.dart test/sound_service_native_test.dart
```

The tests inject a player fake and mock Flutter's haptic channel. They verify all
eight actual bundled assets, distinct paths/data and PCM headers; volume;
disabled/re-enabled behavior; stopping/invalidation on mute; rapid events;
disposal during loading; and synchronous/asynchronous backend and haptic errors.
They do not exercise native decoders, device speakers or physical haptics.

On 2026-11-13, 32 focused Flutter VM tests and 12 Chromium tests passed.
Targeted analysis of the sound service reported no errors or warnings; analysis
of the screen integration timed out. These checks do not replace the native
platform validation below.

## Physical validation still required

All five native platforms remain unvalidated. On each, build/install the app and
check all eight effects, audible distinctions/latency, rapid moves/game end,
volume, mute before and during playback, re-enable, and leaving the game screen.
Exercise audio route changes, unavailable audio devices and app backgrounding.
On Android/iOS, verify supported haptics and system volume/silent settings.
On iOS, check the silent switch explicitly. Check screen reader speech and voice
move recording alongside effects on supported platforms. Verify Linux packages
include required system dependencies and Apple CocoaPods locks resolve cleanly.
Record host/device/OS, build mode and results before checking the platform-test
PLAN item. No physical-device testing or native release builds were performed
for this change.
