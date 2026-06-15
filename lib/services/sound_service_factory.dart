/// Factory for creating the platform-appropriate sound service.

import 'sound_service.dart';
import 'sound_service_impl.dart'
    if (dart.library.js_interop) 'sound_service_impl_web.dart';

/// Create a sound service for the current platform.
///
/// On web: uses Web Audio API tone synthesis via sound_bridge.js.
/// On native: uses SystemSound / HapticFeedback.
SoundService createSoundService() => createPlatformSoundService();
