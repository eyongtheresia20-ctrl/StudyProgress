import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'voice_speaker.dart';

class _WebVoiceSpeaker implements VoiceSpeaker {
  static const _endEvent =
      web.EventStreamProvider<web.SpeechSynthesisEvent>('end');
  static const _errorEvent =
      web.EventStreamProvider<web.SpeechSynthesisErrorEvent>('error');

  StreamSubscription<web.SpeechSynthesisEvent>? _endSub;
  StreamSubscription<web.SpeechSynthesisErrorEvent>? _errSub;
  bool _speaking = false;
  int _utteranceToken = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isSpeaking => _speaking;

  void _clearSubs() {
    _endSub?.cancel();
    _endSub = null;
    _errSub?.cancel();
    _errSub = null;
  }

  @override
  Future<bool> speak(
    String text, {
    required bool isFr,
    double rate = 1.0,
    void Function()? onComplete,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final token = ++_utteranceToken;
    try {
      _clearSubs();
      final synth = web.window.speechSynthesis;
      synth.cancel();

      final utterance = web.SpeechSynthesisUtterance(clean);
      utterance.lang = isFr ? 'fr-FR' : 'en-US';
      utterance.rate = rate.clamp(0.75, 1.6);
      utterance.pitch = 1.02;

      // Pick a matching natural voice when loaded in the browser.
      final voices = synth.getVoices().toDart;
      final langPrefix = isFr ? 'fr' : 'en';
      for (final v in voices) {
        if (v.lang.toLowerCase().startsWith(langPrefix)) {
          utterance.voice = v;
          break;
        }
      }

      void finish() {
        if (token != _utteranceToken) return;
        _speaking = false;
        _clearSubs();
        onComplete?.call();
      }

      _endSub = _endEvent.forTarget(utterance).listen((_) => finish());
      _errSub = _errorEvent.forTarget(utterance).listen((_) => finish());

      _speaking = true;
      synth.speak(utterance);
      return true;
    } catch (_) {
      _speaking = false;
      _clearSubs();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _utteranceToken++;
    _speaking = false;
    _clearSubs();
    try {
      web.window.speechSynthesis.cancel();
    } catch (_) {}
  }
}

VoiceSpeaker createPlatformVoiceSpeaker() => _WebVoiceSpeaker();
