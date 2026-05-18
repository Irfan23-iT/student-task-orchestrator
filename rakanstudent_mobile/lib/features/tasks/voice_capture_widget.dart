import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/api_service.dart';

class VoiceCaptureWidget extends StatefulWidget {
  const VoiceCaptureWidget({super.key, this.apiService, this.onTaskCreated});

  final ApiService? apiService;
  final ValueChanged<AiChatResponse>? onTaskCreated;

  @override
  State<VoiceCaptureWidget> createState() => _VoiceCaptureWidgetState();
}

class _VoiceCaptureWidgetState extends State<VoiceCaptureWidget>
    with SingleTickerProviderStateMixin {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final SpeechToText _speechToText = SpeechToText();

  late final AnimationController _pulseController;
  bool _speechEnabled = false;
  bool _isInitializing = false;
  bool _isListening = false;
  bool _isSubmitting = false;
  String _transcription = '';
  String? _lastSubmittedText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    unawaited(_initializeSpeech());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    unawaited(_speechToText.stop());
    super.dispose();
  }

  Future<void> _initializeSpeech() async {
    if (_speechEnabled || _isInitializing) {
      return;
    }

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    final enabled = await _speechToText.initialize(
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

    if (!mounted) {
      return;
    }

    setState(() {
      _speechEnabled = enabled;
      _isInitializing = false;
      _errorMessage = enabled ? null : 'Speech recognition is unavailable.';
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
      return;
    }

    await _startListening();
  }

  Future<void> _startListening() async {
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
    });

    await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    await _captureFinalTranscription();
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _transcription = result.recognizedWords;
    });

    if (result.finalResult) {
      unawaited(_captureFinalTranscription());
    }
  }

  Future<void> _captureFinalTranscription() async {
    final finalText = _transcription.trim();
    if (finalText.isEmpty || _isSubmitting || finalText == _lastSubmittedText) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.sendChatMessage(finalText);
      if (!mounted) {
        return;
      }

      setState(() {
        _transcription = '';
        _lastSubmittedText = finalText;
        _isSubmitting = false;
      });
      widget.onTaskCreated?.call(response);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Unable to create a task from voice. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final listeningColor = const Color(0xFFEF4444);
    final idleColor = const Color(0xFF7C3AED);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _isListening ? _pulseController.value : 0.0;
              return Container(
                padding: EdgeInsets.all(6 + (pulse * 10)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: listeningColor.withValues(alpha: pulse * 0.16),
                ),
                child: child,
              );
            },
            child: Tooltip(
              message:
                  _isListening
                      ? 'Stop voice capture'
                      : _isSubmitting
                      ? 'Creating task'
                      : 'Start voice task',
              child: FilledButton.tonalIcon(
                onPressed:
                    _isInitializing || _isSubmitting ? null : _toggleListening,
                icon:
                    _isInitializing || _isSubmitting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Icon(
                          _isListening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                        ),
                label: Text(
                  _isSubmitting
                      ? 'Creating'
                      : _isListening
                      ? 'Listening'
                      : 'Voice Task',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _isListening
                          ? listeningColor.withValues(alpha: 0.14)
                          : idleColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  foregroundColor: _isListening ? listeningColor : idleColor,
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
                      _isSubmitting ||
                      _transcription.isNotEmpty ||
                      _errorMessage != null
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
                            _isListening
                                ? listeningColor.withValues(alpha: 0.30)
                                : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      _errorMessage ??
                          (_isSubmitting
                              ? 'Creating a task from your voice...'
                              : _transcription.isEmpty
                              ? 'Listening for your task...'
                              : _transcription),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            _errorMessage == null
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
