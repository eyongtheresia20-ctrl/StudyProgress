import 'dart:async';

import 'voice_speaker_native.dart'
    if (dart.library.js_interop) 'voice_speaker_web.dart' as impl;

abstract class VoiceSpeaker {
  bool get isSupported;
  bool get isSpeaking;

  Future<bool> speak(
    String text, {
    required bool isFr,
    double rate = 1.0,
    void Function()? onComplete,
  });

  Future<void> stop();
}

VoiceSpeaker createVoiceSpeaker() => impl.createPlatformVoiceSpeaker();

