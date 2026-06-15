/// Native sound service implementation.
import 'sound_service.dart';
import 'sound_service_native.dart';

SoundService createPlatformSoundService() => SoundServiceNative();
