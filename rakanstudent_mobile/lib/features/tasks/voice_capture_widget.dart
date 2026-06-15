import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/api_service.dart';

class VoiceCaptureWidget extends StatefulWidget {
  const VoiceCaptureWidget({
    super.key,
    this.apiService,
    this.onTaskCreated,
    this.onClose,
  });

  final ApiService? apiService;
  final ValueChanged<AiChatResponse>? onTaskCreated;
  final VoidCallback? onClose;

  @override
  State<VoiceCaptureWidget> createState() => _VoiceCaptureWidgetState();
}

class _VoiceCaptureWidgetState extends State<VoiceCaptureWidget>
    with TickerProviderStateMixin {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  late final AnimationController _pulseController;
  late final AnimationController _speakingController;
  bool _speechEnabled = false;
  bool _ttsReady = false;
  bool _isSpeaking = false;
  bool _isInitializing = false;
  bool _isListening = false;
  bool _isSubmitting = false;
  bool _isFinalizing = false;
  String _transcription = '';
  String? _errorMessage;
  String? _successMessage;
  Timer? _submitDebounce;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _speakingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_initializeSpeech());
    unawaited(_initializeTts());
  }

  @override
  void dispose() {
    _submitDebounce?.cancel();
    unawaited(_stopSpeaking());
    _pulseController.dispose();
    _speakingController.dispose();
    unawaited(_speechToText.cancel());
    super.dispose();
  }

  Future<void> _initializeTts() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(false);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }

    _flutterTts.setStartHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
      });
      _speakingController.repeat(reverse: true);
    });

    void clearSpeakingState() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
      _speakingController.stop();
      _speakingController.reset();
    }

    _flutterTts.setCompletionHandler(clearSpeakingState);
    _flutterTts.setCancelHandler(clearSpeakingState);
    _flutterTts.setErrorHandler((_) => clearSpeakingState());

    if (!mounted) return;
    setState(() {
      _ttsReady = true;
    });
  }

  Future<void> _speakResponse(String text) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty || !_ttsReady) {
      return;
    }

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(spokenText);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
    });
    _speakingController.stop();
    _speakingController.reset();
  }

  void _handleClose() {
    unawaited(_stopSpeaking());
    widget.onClose?.call();
  }

  Future<void> _initializeSpeech() async {
    if (_speechEnabled || _isInitializing) {
      return;
    }

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    late final bool enabled;
    try {
      enabled = await _speechToText.initialize(
        onError: (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _errorMessage = error.errorMsg;
            _isListening = false;
          });
          _pulseController.stop();
        },
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          final listening = status == 'listening';
          setState(() {
            _isListening = listening;
          });
          if (listening) {
            _pulseController.repeat(reverse: true);
          } else {
            _pulseController.stop();
            _pulseController.reset();
          }
        },
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechEnabled = false;
        _isInitializing = false;
        _errorMessage = 'Speech recognition is unavailable on this device.';
      });
      return;
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechEnabled = false;
        _isInitializing = false;
        _errorMessage =
            error.message ?? 'Speech recognition could not be initialized.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _speechEnabled = enabled;
      _isInitializing = false;
      _errorMessage = enabled ? null : 'Speech recognition is unavailable.';
    });
  }

  Future<void> _resetSpeechRecognizer() async {
    try {
      await _speechToText.cancel();
    } on MissingPluginException {
      // Ignore: resetting should never make the voice sheet crash.
    } on PlatformException {
      // Ignore: a failed cancel still leaves us with a fresh recognizer below.
    }
    _speechToText = SpeechToText();
    if (mounted) {
      setState(() {
        _speechEnabled = false;
        _isInitializing = false;
        _isListening = false;
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
      return;
    }

    if (_transcription.trim().isNotEmpty) {
      await _captureFinalTranscription();
      return;
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    _submitDebounce?.cancel();
    await _stopSpeaking();
    await _resetSpeechRecognizer();

    if (!_speechEnabled) {
      await _initializeSpeech();
    }

    if (!_speechEnabled || _isInitializing) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _transcription = '';
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _speechToText.listen(
        onResult: _handleSpeechResult,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechEnabled = false;
        _isListening = false;
        _errorMessage = 'Speech recognition is unavailable on this device.';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _errorMessage = error.message ?? 'Unable to start voice recording.';
      });
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speechToText.stop();
    } on MissingPluginException {
      // Ignore: stopping should be safe even when the platform plugin is absent.
    } on PlatformException {
      // Ignore: UI state is reset below.
    }
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
    _scheduleCaptureFinalTranscription();
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) {
      return;
    }

    final recognizedWords = result.recognizedWords.trim();
    if (recognizedWords.isEmpty) {
      return;
    }

    setState(() {
      _transcription = recognizedWords;
    });

    if (result.finalResult) {
      setState(() {
        _isListening = false;
      });
      unawaited(_speechToText.stop());
      _scheduleCaptureFinalTranscription();
    }
  }

  void _scheduleCaptureFinalTranscription() {
    _submitDebounce?.cancel();
    _submitDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        unawaited(_captureFinalTranscription());
      }
    });
  }

  Future<void> _captureFinalTranscription() async {
    _submitDebounce?.cancel();
    final finalText = _transcription.trim();
    if (finalText.isEmpty || _isSubmitting || _isFinalizing) {
      return;
    }

    setState(() {
      _isFinalizing = true;
      _isSubmitting = true;
      _isListening = false;
      _errorMessage = null;
    });

    try {
      try {
        await _speechToText.stop();
      } on MissingPluginException {
        // Ignore: submission can continue with the captured transcript.
      } on PlatformException {
        // Ignore: submission can continue with the captured transcript.
      }
      await _stopSpeaking();
      final response = await _apiService.sendChatMessage(
        'Create a task from this voice note. Infer the concise task title, due date or reminder time if mentioned, and priority if obvious. Voice note: "$finalText"',
      );
      if (!mounted) {
        return;
      }

      await _resetSpeechRecognizer();
      final successMessage =
          response.actionPerformed
              ? response.message
              : 'I understood the note, but could not create a task from it.';

      setState(() {
        _transcription = '';
        _isFinalizing = false;
        _isSubmitting = false;
        _successMessage = '$successMessage Tap Voice Task for another.';
      });
      unawaited(_speakResponse(successMessage));
      widget.onTaskCreated?.call(response);
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        _isFinalizing = false;
        _isSubmitting = false;
        _successMessage = null;
        _errorMessage =
            'Voice task creation timed out. The server may be waking up — please try again.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final errorMsg = error.toString().contains('NOT_CONNECTED')
          ? 'Connect Google Calendar first to use voice tasks.'
          : 'Unable to create a task from voice. Please try again.';
      setState(() {
        _isFinalizing = false;
        _isSubmitting = false;
        _successMessage = null;
        _errorMessage = errorMsg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final listeningColor = const Color(0xFFEF4444);
    final idleColor = const Color(0xFF7C3AED);
    final speakingColor = const Color(0xFF20E3B2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: _isSubmitting ? null : _handleClose,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close voice capture',
          ),
        ),
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _pulseController,
              _speakingController,
            ]),
            builder: (context, child) {
              final listeningPulse =
                  _isListening ? _pulseController.value : 0.0;
              final speakingPulse =
                  _isSpeaking ? _speakingController.value : 0.0;
              return Container(
                padding: EdgeInsets.all(
                  6 + (listeningPulse * 10) + (speakingPulse * 6),
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      _isSpeaking
                          ? speakingColor.withValues(
                            alpha: 0.12 + (speakingPulse * 0.12),
                          )
                          : listeningColor.withValues(
                            alpha: listeningPulse * 0.16,
                          ),
                  border:
                      _isSpeaking
                          ? Border.all(
                            color: speakingColor.withValues(
                              alpha: 0.35 + (speakingPulse * 0.35),
                            ),
                            width: 2,
                          )
                          : null,
                ),
                child: child,
              );
            },
            child: Tooltip(
              message:
                  _isListening
                      ? 'Finish voice capture'
                      : _isSpeaking
                      ? 'Stop Rakan speaking'
                      : _isSubmitting
                      ? 'Creating task'
                      : _transcription.trim().isNotEmpty
                      ? 'Create task from transcript'
                      : _successMessage != null
                      ? 'Record another voice task'
                      : 'Start voice task',
              child: FilledButton.tonalIcon(
                onPressed:
                    _isInitializing || _isSubmitting
                        ? null
                        : _isSpeaking
                        ? _stopSpeaking
                        : _toggleListening,
                icon:
                    _isInitializing || _isSubmitting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Icon(
                          _isSpeaking
                              ? Icons.volume_off_rounded
                              : _isListening
                              ? Icons.mic_rounded
                              : _transcription.trim().isNotEmpty
                              ? Icons.check_rounded
                              : Icons.mic_none_rounded,
                        ),
                label: Text(
                  _isSubmitting
                      ? 'Creating'
                      : _isSpeaking
                      ? 'Stop Audio'
                      : _isListening
                      ? 'Recording'
                      : _transcription.trim().isNotEmpty
                      ? 'Create Task'
                      : _successMessage != null
                      ? 'Record Again'
                      : 'Voice Task',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _isSpeaking
                          ? speakingColor.withValues(alpha: 0.16)
                          : _isListening
                          ? listeningColor.withValues(alpha: 0.14)
                          : idleColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  foregroundColor:
                      _isSpeaking
                          ? speakingColor
                          : _isListening
                          ? listeningColor
                          : idleColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child:
              _isListening ||
                      _isSpeaking ||
                      _isSubmitting ||
                      _transcription.isNotEmpty ||
                      _errorMessage != null ||
                      _successMessage != null
                  ? Container(
                    key: const ValueKey<String>('voice-transcript-banner'),
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            _isSpeaking
                                ? speakingColor.withValues(alpha: 0.45)
                                : _isListening
                                ? listeningColor.withValues(alpha: 0.30)
                                : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSpeaking) ...[
                          _SpeakingWave(
                            animation: _speakingController,
                            color: speakingColor,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          _errorMessage ??
                              _successMessage ??
                              (_isSubmitting
                                  ? 'Creating a task from your voice...'
                                  : _isSpeaking
                                  ? 'Rakan is speaking...'
                                  : _transcription.isEmpty
                                  ? 'Listening for your task...'
                                  : _transcription),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                _errorMessage == null
                                    ? _successMessage == null
                                        ? theme.colorScheme.onSurface
                                        : const Color(0xFF16A34A)
                                    : theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SpeakingWave extends StatelessWidget {
  const _SpeakingWave({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final phase = (animation.value + (index * 0.18)) % 1.0;
            final height = 8 + (phase * 18);
            return Container(
              width: 5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.45 + (phase * 0.45)),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
    );
  }
}
