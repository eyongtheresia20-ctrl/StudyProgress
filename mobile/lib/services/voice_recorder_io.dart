import 'voice_recorder.dart';

class _IoVoiceRecorder implements VoiceRecorder {
  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<bool> start({
    String language = 'en',
    void Function(double level)? onLevel,
  }) async =>
      false;

  @override
  Future<StoppedRecording> stop() async => (clip: null, transcript: '');

  @override
  void dispose() {}
}

VoiceRecorder createVoiceRecorderImpl() => _IoVoiceRecorder();
