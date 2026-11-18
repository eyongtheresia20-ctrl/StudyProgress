import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_recorder.dart';

class _WebVoiceRecorder implements VoiceRecorder {
  static const _dataEvent =
      web.EventStreamProvider<web.BlobEvent>('dataavailable');
  static const _stopEvent = web.EventStreamProvider<web.Event>('stop');

  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  web.AudioContext? _audioCtx;
  Timer? _meterTimer;
  StreamSubscription<web.BlobEvent>? _dataSub;
  final List<web.Blob> _chunks = [];
  bool _recording = false;

  @override
  bool get isSupported => true;

  @override
  bool get isRecording => _recording;

  void _startMetering(
    web.MediaStream stream,
    void Function(double level)? onLevel,
  ) {
    if (onLevel == null) return;
    try {
      final ctx = web.AudioContext();
      final src = ctx.createMediaStreamSource(stream);
      final analyser = ctx.createAnalyser()..fftSize = 64;
      src.connect(analyser);
      final jsArr = Uint8List(analyser.frequencyBinCount).toJS;
      _audioCtx = ctx;

      _meterTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (!_recording) return;
        analyser.getByteTimeDomainData(jsArr);
        final samples = jsArr.toDart;
        var peak = 0.0;
        for (final v in samples) {
          final delta = (v - 128).abs() / 128.0;
          if (delta > peak) peak = delta;
        }
        onLevel((peak * 2.4).clamp(0.05, 1.0));
      });
    } catch (_) {
      _meterTimer = Timer.periodic(const Duration(milliseconds: 120), (t) {
        if (_recording) onLevel(0.25 + ((t.tick % 4) * 0.15));
      });
    }
  }

  void _stopMetering() {
    _meterTimer?.cancel();
    _meterTimer = null;
    try {
      _audioCtx?.close();
    } catch (_) {}
    _audioCtx = null;
  }

  @override
  Future<bool> start({
    String language = 'en',
    void Function(double level)? onLevel,
  }) async {
    if (_recording) return true;
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;

      final recorder = web.MediaRecorder(stream);
      _chunks.clear();
      _dataSub = _dataEvent.forTarget(recorder).listen((event) {
        if (event.data.size > 0) {
          _chunks.add(event.data);
        }
      });

      _stream = stream;
      _recorder = recorder;
      // Single-container start() produces cleaner complete audio bytes for Gemini.
      recorder.start();
      _recording = true;
      _startMetering(stream, onLevel);
      return true;
    } catch (_) {
      dispose();
      return false;
    }
  }

  @override
  Future<StoppedRecording> stop() async {
    _stopMetering();
    final recorder = _recorder;
    if (!_recording || recorder == null) {
      return (clip: null, transcript: '');
    }

    final completer = Completer<StoppedRecording>();
    late StreamSubscription<web.Event> stopSub;

    stopSub = _stopEvent.forTarget(recorder).listen((_) async {
      await stopSub.cancel();
      await _dataSub?.cancel();
      _dataSub = null;

      final mime =
          recorder.mimeType.isNotEmpty ? recorder.mimeType : 'audio/webm';
      final blob = web.Blob(
        _chunks.toJS,
        web.BlobPropertyBag(type: mime),
      );
      final buffer = await blob.arrayBuffer().toDart;
      final bytes = Uint8List.fromList(buffer.toDart.asUint8List());

      _stopTracks();
      _recording = false;
      _recorder = null;
      _chunks.clear();

      if (!completer.isCompleted) {
        if (bytes.isEmpty) {
          completer.complete((clip: null, transcript: ''));
        } else {
          final ext = mime.contains('ogg') ? 'ogg' : 'webm';
          completer.complete((
            clip: (
              name: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
              mimeType: mime.split(';').first.trim(),
              bytes: bytes,
            ),
            transcript: '',
          ));
        }
      }
    });

    recorder.stop();
    return completer.future;
  }

  void _stopTracks() {
    final tracks = _stream?.getTracks().toDart ?? const <web.MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }
    _stream = null;
  }

  @override
  void dispose() {
    _stopMetering();
    _dataSub?.cancel();
    _dataSub = null;
    if (_recording) {
      try {
        _recorder?.stop();
      } catch (_) {}
    }
    _stopTracks();
    _recorder = null;
    _recording = false;
    _chunks.clear();
  }
}

VoiceRecorder createVoiceRecorderImpl() => _WebVoiceRecorder();
