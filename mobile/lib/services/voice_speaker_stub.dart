import 'voice_speaker.dart';

class _StubVoiceSpeaker implements VoiceSpeaker {
  @override
  bool get isSupported => false;

  @override
  bool get isSpeaking => false;

  @override
  Future<bool> speak(
    String text, {
    required bool isFr,
    double rate = 1.0,
    void Function()? onComplete,
  }) async {
    return false;
  }

  @override
  Future<void> stop() async {}
}

VoiceSpeaker createPlatformVoiceSpeaker() => _StubVoiceSpeaker();

