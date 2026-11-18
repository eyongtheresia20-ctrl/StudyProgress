import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'voice_speaker.dart';

class NativeVoiceSpeaker implements VoiceSpeaker {
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  void Function()? _onComplete;

  NativeVoiceSpeaker() {
    _initTts();
  }

  void _initTts() {
    _tts.setStartHandler(() {
      _speaking = true;
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      _onComplete?.call();
      _onComplete = null;
    });
    _tts.setErrorHandler((dynamic msg) {
      _speaking = false;
      _onComplete?.call();
      _onComplete = null;
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      _onComplete = null;
    });
  }

  @override
  bool get isSupported => !kIsWeb;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<bool> speak(
    String text, {
    required bool isFr,
    double rate = 1.0,
    void Function()? onComplete,
  }) async {
    if (kIsWeb) return false;
    _onComplete = onComplete;
    try {
      await _tts.stop();
      final lang = isFr ? 'fr-FR' : 'en-US';
      await _tts.setLanguage(lang);
      await _tts.setSpeechRate((rate * 0.48).clamp(0.1, 1.0));
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _speaking = true;
      final res = await _tts.speak(text);
      return res == 1;
    } catch (_) {
      _speaking = false;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    _onComplete = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

VoiceSpeaker createPlatformVoiceSpeaker() => NativeVoiceSpeaker();

