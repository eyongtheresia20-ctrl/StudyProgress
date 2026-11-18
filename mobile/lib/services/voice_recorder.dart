import 'voice_recorder_io.dart'
    if (dart.library.js_interop) 'voice_recorder_web.dart' as impl;

typedef RecordedAudioClip = ({String name, String mimeType, List<int> bytes});
typedef StoppedRecording = ({RecordedAudioClip? clip, String transcript});

abstract class VoiceRecorder {
  bool get isSupported;
  bool get isRecording;

  Future<bool> start({
    String language = 'en',
    void Function(double level)? onLevel,
  });
  Future<StoppedRecording> stop();
  void dispose();
}

VoiceRecorder createVoiceRecorder() => impl.createVoiceRecorderImpl();
