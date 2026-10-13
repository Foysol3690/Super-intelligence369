import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  bool get isListening => _speech.isListening;

  Future<bool> init({
    required void Function(String status) onStatus,
    required void Function(SpeechRecognitionError error) onError,
  }) async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(onStatus: onStatus, onError: onError);
      return _ready;
    } catch (_) {
      return false;
    }
  }

  /// [listenFor]/[pauseFor] are overridable per call because one session
  /// length does not fit every caller: passive wake-word listening should
  /// run as long as the platform allows to minimize how often a session
  /// restarts (each restart re-opens the native recognizer, which is the
  /// likely source of a start/stop sound on some Android builds — this
  /// package does not expose a way to suppress that tone, so lowering
  /// restart frequency is the real mitigation available here), while active
  /// command listening and barge-in should stay short and responsive.
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) =>
            onResult(r.recognizedWords, r.finalResult),
        onSoundLevelChange: (dB) => onLevel(((dB + 2) / 12).clamp(0.0, 1.0)),
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
