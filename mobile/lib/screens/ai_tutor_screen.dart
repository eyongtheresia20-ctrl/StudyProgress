import 'dart:async';

import 'dart:convert';

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';

import '../models/study_models.dart';

import '../providers/study_provider.dart';

import '../services/link_opener.dart';

import '../services/voice_recorder.dart';
import '../services/supabase_cloud_service.dart' hide cleanMathNotation;

import '../widgets/teacher_notes_view.dart';

enum AiMode { ask, quiz, summary }

class _ChatMessage {
  final String role; // 'user' or 'assistant'

  final String text;

  final List<Uint8List> images;

  final SimulationData? simulation;

  final String? modelUsed;

  final DateTime timestamp;

  _ChatMessage({
    required this.role,

    required this.text,

    this.images = const [],

    this.simulation,

    this.modelUsed,

    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AiTutorScreen extends StatefulWidget {
  final int? initialProgressionId;

  final String? initialSubjectName;

  final String? initialTopicTitle;

  final VoidCallback? onBack;

  const AiTutorScreen({
    super.key,

    this.initialProgressionId,

    this.initialSubjectName,

    this.initialTopicTitle,

    this.onBack,
  });

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  static const Color _deepNavy = Color(0xFF13346B);

  static const Color _primaryBlue = Color(0xFF2563EB);

  static const Color _aiPurple = Color(0xFF7C3AED);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController _questionCtrl = TextEditingController();

  final TextEditingController _historySearchCtrl = TextEditingController();

  final VoiceRecorder _voiceRecorder = createVoiceRecorder();

  AiMode _mode = AiMode.ask;

  int? _selectedProgressionId;

  String? _customSubject;

  String? _customTopic;

  bool _isGeneralChat = false;

  bool _askLoading = false;

  bool _quizLoading = false;

  bool _summaryLoading = false;

  bool get _loading => _askLoading || _quizLoading || _summaryLoading;

  bool get _isCurrentModeLoading {
    switch (_mode) {
      case AiMode.ask:
        return _askLoading;

      case AiMode.quiz:
        return _quizLoading;

      case AiMode.summary:
        return _summaryLoading;
    }
  }

  String? _lastLanguageCode;

  bool _grading = false;

  final List<_ChatMessage> _chatMessages = [];
  static final List<_ChatMessage> _persistedChatMessages = [];
  static int? _persistedProgressionId;
  static String? _persistedSubject;
  static String? _persistedTopic;
  static bool _persistedIsGeneral = false;

  void _syncPersistedChat() {
    _persistedChatMessages.clear();
    _persistedChatMessages.addAll(_chatMessages);
    _persistedProgressionId = _selectedProgressionId;
    _persistedSubject = _customSubject;
    _persistedTopic = _customTopic;
    _persistedIsGeneral = _isGeneralChat;
  }

  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,

          duration: const Duration(milliseconds: 300),

          curve: Curves.easeOut,
        );
      }
    });
  }

  // Dedicated per-mode workspaces so Ask AI, Quiz Me, and Summary stay clean.

  String? _askOutput;

  String? _askModelUsed;

  SimulationData? _askSimulation;

  String? _summaryOutput;

  String? _summaryModelUsed;

  List<Map<String, String>> _summarySources = [];

  List<NoteDiagram> _summaryDiagrams = [];

  SimulationData? _summarySimulation;

  final List<({String question, String answer, SimulationData? simulation})>
  _summaryFollowUps = [];

  String? _quizModelUsed;

  final List<({String question, String answer, SimulationData? simulation})>
  _quizFollowUps = [];

  List<QuizQuestion> _quiz = [];

  final Map<int, int> _selectedAnswers = {};

  final Map<int, TextEditingController> _openAnswerCtrls = {};

  final TextEditingController _quizNoteCtrl = TextEditingController();

  final List<({String name, Uint8List bytes})> _quizPaperImages = [];

  String? _quizFeedback;

  String? _scoreSummary;

  SimulationData? _simulation;

  // Multimodal attachments (Pictures + Audio)

  final List<({String name, Uint8List bytes})> _attachedImages = [];

  ({String name, Uint8List bytes})? _attachedAudio;

  bool _recording = false;

  bool _transcribing = false;

  String _textBeforeRecording = '';

  final List<double> _voiceLevels = List.filled(28, 0.14, growable: true);

  // Search / chat history state
  static List<AiHistoryItem> _cachedHistory = [];

  List<AiHistoryItem> _history = [];

  bool _historyLoading = false;

  String _historyQuery = '';

  String? _activeLanguage;

  bool _translating = false;

  final Map<
    String,
    ({
      String content,
      List<NoteDiagram> diagrams,
      List<Map<String, String>> sources,
      String? modelUsed,
      SimulationData? simulation,
    })
  >
  _summaryByLang = {};

  final Map<String, ({List<QuizQuestion> quiz, String? modelUsed})>
  _quizByLang = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final provider = context.watch<StudyProvider>();

    final currentLang = provider.languageCode;

    if (_lastLanguageCode != null && _lastLanguageCode != currentLang) {
      _lastLanguageCode = currentLang;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleLanguageChange(provider, currentLang);
        }
      });
    } else {
      _lastLanguageCode = currentLang;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _autoTranslateQuizIfNeeded(provider);
          _autoTranslateSummaryIfNeeded(provider);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();

    final hasInitial = widget.initialProgressionId != null ||
        (widget.initialTopicTitle != null && widget.initialTopicTitle!.isNotEmpty);

    if (!hasInitial && _persistedChatMessages.isNotEmpty) {
      _chatMessages.addAll(_persistedChatMessages);
      _selectedProgressionId = _persistedProgressionId;
      _customSubject = _persistedSubject;
      _customTopic = _persistedTopic;
      _isGeneralChat = _persistedIsGeneral;
      _mode = AiMode.ask;
      _scrollToBottom();
    } else {
      _selectedProgressionId = widget.initialProgressionId;
      _customSubject = widget.initialSubjectName;
      _customTopic = widget.initialTopicTitle;
      _isGeneralChat = false;
      _mode = AiMode.summary;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();

      if (mounted) {
        if (!hasInitial && _persistedChatMessages.isNotEmpty) {
          // Already restored the active conversation; stay right here!
          return;
        }

        final p = context.read<StudyProvider>();

        final s = AppStrings(p.languageCode);

        if (_selectedProgressionId == null &&
            (_customTopic == null || _customTopic!.isEmpty)) {
          final topics = _combinedCurriculumTopics(p.studentHome);

          if (topics.isNotEmpty) {
            setState(() {
              _selectedProgressionId = topics.first.id;
            });
          }
        }

        if (_selectedProgressionId != null ||
            (_customTopic != null && _customTopic!.isNotEmpty)) {
          _runAiAction(p, s);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant AiTutorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final progressionChanged =
        widget.initialProgressionId != null &&
        widget.initialProgressionId != oldWidget.initialProgressionId;
    final topicChanged =
        widget.initialTopicTitle != null &&
        widget.initialTopicTitle != oldWidget.initialTopicTitle;

    if (progressionChanged) {
      setState(() {
        _isGeneralChat = false;

        _mode = AiMode.summary;

        _selectedProgressionId = widget.initialProgressionId;

        _customSubject = null;

        _customTopic = null;

        _resetTopicWorkspace();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final p = context.read<StudyProvider>();

          final s = AppStrings(p.languageCode);

          _runAiAction(p, s);
        }
      });
    } else if (topicChanged) {
      setState(() {
        _isGeneralChat = false;

        _mode = AiMode.summary;

        _selectedProgressionId = null;

        _customSubject = widget.initialSubjectName;

        _customTopic = widget.initialTopicTitle;

        _resetTopicWorkspace();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final p = context.read<StudyProvider>();

          final s = AppStrings(p.languageCode);

          _runAiAction(p, s);
        }
      });
    }
  }

  @override
  void dispose() {
    _voiceRecorder.dispose();

    _questionCtrl.dispose();

    _historySearchCtrl.dispose();

    _quizNoteCtrl.dispose();

    for (final ctrl in _openAnswerCtrls.values) {
      ctrl.dispose();
    }

    super.dispose();
  }

  TextEditingController _ctrlForQuestion(int index) {
    return _openAnswerCtrls.putIfAbsent(index, () => TextEditingController());
  }

  void _clearQuizState() {
    _quiz = [];

    _quizModelUsed = null;

    _quizFollowUps.clear();

    _selectedAnswers.clear();

    for (final ctrl in _openAnswerCtrls.values) {
      ctrl.dispose();
    }

    _openAnswerCtrls.clear();

    _quizNoteCtrl.clear();

    _quizPaperImages.clear();

    _quizFeedback = null;

    _scoreSummary = null;

    _simulation = null;
  }

  void _resetTopicWorkspace() {
    _chatMessages.clear();

    _questionCtrl.clear();

    _attachedImages.clear();

    _attachedAudio = null;

    _askOutput = null;

    _askModelUsed = null;

    _askSimulation = null;

    _summaryOutput = null;

    _summaryModelUsed = null;

    _summarySources = [];

    _summaryDiagrams = [];

    _summarySimulation = null;

    _summaryFollowUps.clear();

    _clearQuizState();
  }

  Future<void> _loadHistory({bool forceIndicator = false}) async {
    if (!mounted) return;

    final provider = context.read<StudyProvider>();

    if (!provider.isAuthenticated) return;

    if (_cachedHistory.isNotEmpty && _history.isEmpty) {
      setState(() => _history = List.from(_cachedHistory));
    }

    if (forceIndicator || (_history.isEmpty && _cachedHistory.isEmpty)) {
      setState(() => _historyLoading = true);
    }

    try {
      final items = await provider.api.getAiHistory(limit: 25);

      _cachedHistory = List.from(items);

      if (mounted) {
        setState(() => _history = items);
      }
    } catch (_) {
      // Keep UI smooth if history request fails transiently.
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _openHistoryDrawer() {
    if (_cachedHistory.isNotEmpty && _history.isEmpty) {
      _history = List.from(_cachedHistory);
    }

    _loadHistory(forceIndicator: false);

    _scaffoldKey.currentState?.openDrawer();
  }

  void _startNewSearch() {
    setState(() {
      _isGeneralChat = true;
      _selectedProgressionId = null;
      _customTopic = null;
      _customSubject = null;
      _mode = AiMode.ask;
      _resetTopicWorkspace();
      _persistedChatMessages.clear();
      _syncPersistedChat();
      _quizFollowUps.clear();
      _summaryFollowUps.clear();
      _attachedImages.clear();
      _attachedAudio = null;
      _questionCtrl.clear();
    });

    final s = AppStrings(context.read<StudyProvider>().languageCode);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.isFr
              ? 'Nouvelle conversation libre — Sans matière imposée'
              : 'New open chat — No forced curriculum subject',
        ),

        duration: const Duration(seconds: 2),

        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<QuizQuestion> _parseQuizFromHistory(AiHistoryItem item) {
    if (item.quiz != null && item.quiz!.isNotEmpty) {
      return item.quiz!;
    }

    try {
      final decoded = jsonDecode(item.response);

      if (decoded is List) {
        return decoded
            .map(
              (e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
    } catch (_) {}

    return [];
  }

  bool _sameHistoryLesson(AiHistoryItem a, AiHistoryItem b) {
    if (a.progressionId != null && b.progressionId != null) {
      return a.progressionId == b.progressionId;
    }

    final ta = (a.topicTitle ?? '').trim().toLowerCase();
    final tb = (b.topicTitle ?? '').trim().toLowerCase();

    if (ta.isNotEmpty && ta == tb) return true;

    // For open chats (progressionId == null and topicTitle empty):
    // If both are chats and created within 4 hours, they belong to the SAME dialogue session!
    if (a.interactionType == 'chat' && b.interactionType == 'chat') {
      if (a.progressionId == null && b.progressionId == null) {
        if (a.createdAt != null && b.createdAt != null) {
          final diff = a.createdAt!.difference(b.createdAt!).abs();
          return diff.inHours < 4;
        }
        return true;
      }
    }

    return false;
  }

  void _loadHistoryItem(AiHistoryItem item, {bool popDrawer = true}) {
    if (popDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    var nextMode = AiMode.ask;

    if (item.interactionType == 'quiz' ||
        item.interactionType == 'simulation') {
      nextMode = AiMode.quiz;
    } else if (item.interactionType == 'summary') {
      nextMode = AiMode.summary;
    }

    // Gather all history entries for this same lesson (_history is newest-first)
    // so restoring a lesson brings back its complete Summary, Quiz, and Ask AI state.
    final siblings = _history
        .where((h) => _sameHistoryLesson(h, item))
        .toList();

    AiHistoryItem? latestSummary = item.interactionType == 'summary'
        ? item
        : null;

    AiHistoryItem? latestQuiz = item.interactionType == 'quiz' ? item : null;

    AiHistoryItem? latestGraded = item.interactionType == 'simulation'
        ? item
        : null;

    AiHistoryItem? latestChat = item.interactionType == 'chat' ? item : null;

    for (final h in siblings) {
      if (latestSummary == null && h.interactionType == 'summary') {
        latestSummary = h;
      } else if (latestQuiz == null && h.interactionType == 'quiz') {
        latestQuiz = h;
      } else if (latestGraded == null && h.interactionType == 'simulation') {
        latestGraded = h;
      } else if (latestChat == null && h.interactionType == 'chat') {
        latestChat = h;
      }
    }

    final quizSource = latestGraded ?? latestQuiz;

    final parsedQuiz = quizSource != null
        ? _parseQuizFromHistory(quizSource)
        : (latestQuiz != null
              ? _parseQuizFromHistory(latestQuiz)
              : <QuizQuestion>[]);

    final resolvedQuiz = parsedQuiz.isNotEmpty
        ? parsedQuiz
        : (latestQuiz != null
              ? _parseQuizFromHistory(latestQuiz)
              : <QuizQuestion>[]);

    setState(() {
      _resetTopicWorkspace();

      _mode = nextMode;

      // Collect ALL chat turns belonging to this session, sorted chronologically (oldest to newest)
      final chatSiblings = siblings
          .where((h) => h.interactionType == 'chat')
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

      if (chatSiblings.isNotEmpty) {
        _chatMessages.clear();
        for (final c in chatSiblings) {
          _chatMessages.add(_ChatMessage(role: 'user', text: c.prompt));
          _chatMessages.add(
            _ChatMessage(
              role: 'assistant',
              text: c.response,
              simulation: c.simulation,
              modelUsed: 'history',
            ),
          );
        }
        _syncPersistedChat();
        _questionCtrl.clear();
        final last = chatSiblings.last;
        _askOutput = last.response;
        _askModelUsed = 'history';
        _askSimulation = last.simulation;
        _scrollToBottom();
      }

      if (latestSummary != null) {
        var cleanResp = latestSummary.response;

        if (cleanResp.trim().startsWith('{') && cleanResp.contains('"notes"')) {
          final m = RegExp(
            r'"notes"\s*:\s*"((?:[^"\\]|\\.)*)"',
          ).firstMatch(cleanResp);

          if (m != null) {
            try {
              cleanResp = jsonDecode('"${m.group(1)}"') as String;
            } catch (_) {}
          }
        }

        _summaryOutput = cleanResp;

        _summaryModelUsed = 'history';

        _summarySources = latestSummary.sources;

        _summaryDiagrams = latestSummary.diagrams;

        _summarySimulation = latestSummary.simulation;
      }

      if (quizSource != null || resolvedQuiz.isNotEmpty) {
        _quiz = resolvedQuiz;

        _quizModelUsed = 'history';

        _scoreSummary = latestGraded?.scoreSummary ?? quizSource?.scoreSummary;

        _simulation = latestGraded?.simulation ?? quizSource?.simulation;

        _quizFeedback = latestGraded != null
            ? latestGraded.response
            : (resolvedQuiz.isEmpty ? quizSource?.response : null);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final p = context.read<StudyProvider>();
            _autoTranslateQuizIfNeeded(p);
            _autoTranslateSummaryIfNeeded(p);
          }
        });
      }

      final provider = context.read<StudyProvider>();

      final topics = _combinedCurriculumTopics(provider.studentHome);

      final hasProgInTopics =
          item.progressionId != null &&
          topics.any((t) => t.id == item.progressionId);

      if (hasProgInTopics) {
        _isGeneralChat = false;

        _selectedProgressionId = item.progressionId;

        _customSubject = null;

        _customTopic = null;
      } else if ((item.topicTitle ?? '').isNotEmpty) {
        _isGeneralChat = false;

        _selectedProgressionId = null;

        _customSubject = item.subjectName;

        _customTopic = item.topicTitle;
      } else {
        _isGeneralChat = true;
      }
    });
  }

  Future<void> _pickImages() async {
    try {
      const imageGroup = XTypeGroup(
        label: 'Pictures',

        extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      );

      final files = await openFiles(acceptedTypeGroups: const [imageGroup]);

      if (!mounted || files.isEmpty) return;

      final picked = <({String name, Uint8List bytes})>[];

      for (final f in files.take(4)) {
        final bytes = await f.readAsBytes();

        if (bytes.isNotEmpty) {
          picked.add((name: f.name, bytes: bytes));
        }
      }

      if (!mounted || picked.isEmpty) return;

      setState(() => _attachedImages.addAll(picked));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick picture: $e')));
    }
  }

  void _applySpokenText(String spoken) {
    final clean = spoken.trim();

    if (clean.isEmpty) return;

    final prefix = _textBeforeRecording.trim();

    final combined = prefix.isEmpty ? clean : '$prefix $clean';

    _questionCtrl.value = TextEditingValue(
      text: combined,

      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  Future<bool> _transcribeAudioToText(
    String filename,

    Uint8List bytes,

    String lang,
  ) async {
    if (!mounted) return false;

    final provider = context.read<StudyProvider>();

    setState(() => _transcribing = true);

    try {
      final res = await provider.api.transcribeAudio(
        filename: filename,

        bytes: bytes,

        language: lang,
      );

      if (!mounted) return false;

      if (res.text.isNotEmpty) {
        setState(() => _applySpokenText(res.text));

        return true;
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      const audioGroup = XTypeGroup(
        label: 'Audio Files',

        extensions: ['mp3', 'wav', 'm4a', 'ogg', 'webm', 'aac'],
      );

      final file = await openFile(acceptedTypeGroups: const [audioGroup]);

      if (!mounted || file == null) return;

      final bytes = await file.readAsBytes();

      if (!mounted || bytes.isEmpty) return;

      final lang = context.read<StudyProvider>().languageCode;

      _textBeforeRecording = _questionCtrl.text;

      final ok = await _transcribeAudioToText(file.name, bytes, lang);

      if (!mounted) return;

      if (!ok) {
        // Fallback to attaching audio only if transcription didn't yield text.

        setState(() => _attachedAudio = (name: file.name, bytes: bytes));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick audio: $e')));
    }
  }

  Future<void> _startVoiceRecording(AppStrings s) async {
    if (!_voiceRecorder.isSupported) {
      await _pickAudioFile();

      return;
    }

    _textBeforeRecording = _questionCtrl.text;

    final started = await _voiceRecorder.start(
      language: s.lang,

      onLevel: (level) {
        if (!mounted || !_recording) return;

        setState(() {
          _voiceLevels.removeAt(0);

          _voiceLevels.add(level);
        });
      },
    );

    if (!mounted) return;

    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Microphone inaccessible — choisissez un fichier audio à la place.'
                : 'Microphone unavailable — choose an audio file instead.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _recording = true;

      for (var i = 0; i < _voiceLevels.length; i++) {
        _voiceLevels[i] = 0.14;
      }
    });
  }

  Future<void> _cancelVoiceRecording() async {
    await _voiceRecorder.stop();

    if (!mounted) return;

    setState(() {
      _recording = false;

      _questionCtrl.value = TextEditingValue(
        text: _textBeforeRecording,

        selection: TextSelection.collapsed(offset: _textBeforeRecording.length),
      );
    });
  }

  Future<void> _finishVoiceRecording(
    StudyProvider provider,

    AppStrings s, {

    required bool autoSend,
  }) async {
    final stopped = await _voiceRecorder.stop();

    if (!mounted) return;

    setState(() => _recording = false);

    if (stopped.clip == null) return;

    final audioBytes = Uint8List.fromList(stopped.clip!.bytes);

    final transcribed = await _transcribeAudioToText(
      stopped.clip!.name,

      audioBytes,

      s.lang,
    );

    if (!mounted) return;

    if (!transcribed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Impossible de transcrire la voix. Veuillez réessayer.'
                : 'Could not transcribe voice recording. Please try again.',
          ),
        ),
      );

      return;
    }

    if (autoSend && _questionCtrl.text.trim().isNotEmpty) {
      await _sendComposerPrompt(provider, s);
    }
  }

  Future<void> _pickQuizPaperImages() async {
    try {
      const imageGroup = XTypeGroup(
        label: 'Handwritten Paper Photos',

        extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      );

      final files = await openFiles(acceptedTypeGroups: const [imageGroup]);

      if (!mounted || files.isEmpty) return;

      final picked = <({String name, Uint8List bytes})>[];

      for (final f in files.take(5)) {
        final bytes = await f.readAsBytes();

        if (bytes.isNotEmpty) {
          picked.add((name: f.name, bytes: bytes));
        }
      }

      if (!mounted || picked.isEmpty) return;

      setState(() => _quizPaperImages.addAll(picked));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick paper photo: $e')));
    }
  }

  Future<void> _refreshProgressSilently(StudyProvider provider) async {
    try {
      await provider.refreshDashboard();
    } catch (_) {
      // Do not interrupt tutor output if dashboard refresh fails transiently.
    }
  }

  Future<void> _markUnderstanding(
    StudyProvider provider,

    AppStrings s,

    int progId, {

    required String status,

    required String understandingLevel,
  }) async {
    try {
      await provider.updateTopicProgress(
        progressionId: progId,

        status: status,

        understandingLevel: understandingLevel,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            understandingLevel == 'full'
                ? (s.isFr
                      ? 'Sujet marqué comme maîtrisé dans Ma Progression !'
                      : 'Topic marked understood in My Progress!')
                : (s.isFr
                      ? 'Sujet marqué à réviser dans Ma Progression.'
                      : 'Topic flagged for revision in My Progress.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Progress update failed: $e')));
    }
  }

  static String _cleanDisplaySubject(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();

    s = s.replaceAll(
      RegExp(
        r'^(?:[A-Z]{1,4}|classe(?:\s+de(?:\s+[^\-]+)?)?|form\s+\d+|lower\s+sixth|upper\s+sixth)\s*[-–:]\s*',

        caseSensitive: false,
      ),

      '',
    );

    s = s.replaceAll(
      RegExp(r'^(?:all|tous|tout)\s*[-–:]\s*', caseSensitive: false),

      '',
    );

    s = s.replaceAll('\ufffd', 'e');

    if (s.contains(' - ')) {
      final parts = s.split(' - ');

      if (parts[0].trim().split(' ').length <= 4 &&
          parts[0].trim().length <= 32) {
        s = parts[0];
      }
    }

    return s.trim();
  }

  List<OfficialProgression> _combinedCurriculumTopics(StudentHomeData? home) {
    if (home == null) return const [];

    final allowed = home.classSubjects
        .map((s) => _cleanDisplaySubject(s).toLowerCase())
        .where((s) => s.length > 2)
        .toSet();

    final combined = <OfficialProgression>[];

    final seen = <String>{};

    for (final t in home.allTopics) {
      final cleanSubj = _cleanDisplaySubject(t.subjectName);

      final lowSubj = cleanSubj.toLowerCase();

      if (allowed.isNotEmpty && !allowed.contains(lowSubj)) {
        continue;
      }

      final key = '$lowSubj::${t.topicTitle.toLowerCase()}';

      if (!seen.add(key)) continue;

      combined.add(
        OfficialProgression(
          id: t.id,

          subsystemId: t.subsystemId,

          subsystemName: t.subsystemName,

          classId: t.classId,

          className: t.className,

          subjectName: cleanSubj,

          topicTitle: t.topicTitle,

          subtopics: t.subtopics,

          weekNumber: t.weekNumber,

          startDate: t.startDate,

          endDate: t.endDate,

          studyDays: t.studyDays,

          studentStatus: t.studentStatus,

          understandingLevel: t.understandingLevel,
        ),
      );
    }

    return combined;
  }

  ({int? progId, String? subject, String? topic}) _resolveSelectedTarget(
    StudentHomeData? home,
  ) {
    if (_isGeneralChat) {
      return (progId: null, subject: null, topic: null);
    }

    final hasCustom = _customTopic != null && _customTopic!.isNotEmpty;

    if (hasCustom) {
      return (progId: null, subject: _customSubject, topic: _customTopic);
    }

    final topics = _combinedCurriculumTopics(home);

    if (topics.isEmpty) {
      return (progId: null, subject: null, topic: null);
    }

    final selected = topics.firstWhere(
      (t) => t.id == _selectedProgressionId,

      orElse: () => topics.first,
    );

    if (_selectedProgressionId != selected.id) {
      _selectedProgressionId = selected.id;
    }

    return (
      progId: selected.id < 0 ? null : selected.id,

      subject: selected.subjectName,

      topic: selected.topicTitle,
    );
  }

  Future<void> _gradeQuizSubmission(
    StudyProvider provider,

    AppStrings s,
  ) async {
    final target = _resolveSelectedTarget(provider.studentHome);

    final progId = target.progId;

    final typedAnswers = <String, dynamic>{};

    for (var i = 0; i < _quiz.length; i++) {
      final q = _quiz[i];

      if (q.isMcq) {
        final sel = _selectedAnswers[i];

        if (sel != null && sel >= 0 && sel < q.options.length) {
          typedAnswers['Q${i + 1}'] = q.options[sel];
        }
      } else {
        final txt = _ctrlForQuestion(i).text.trim();

        if (txt.isNotEmpty) {
          typedAnswers['Q${i + 1}'] = txt;
        }
      }
    }

    if (typedAnswers.isEmpty &&
        _quizPaperImages.isEmpty &&
        _quizNoteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Répondez aux questions ou importez la photo de votre feuille.'
                : 'Answer at least one question or upload a photo of your handwritten paper.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _grading = true;

      _quizFeedback = null;

      _scoreSummary = null;

      _simulation = null;
    });

    try {
      final res = await provider.api.gradeQuizSubmission(
        progressionId: progId,

        subjectName: _customSubject,

        topicTitle: _customTopic,

        quiz: _quiz,

        typedAnswers: typedAnswers,

        note: _quizNoteCtrl.text.trim(),

        paperImages: _quizPaperImages
            .map((e) => (name: e.name, bytes: e.bytes))
            .toList(),
      );

      if (!mounted) return;

      setState(() {
        _quizFeedback = res.content;

        _scoreSummary = res.scoreSummary;

        _simulation = res.simulation;

        _quizModelUsed = res.modelUsed;
      });

      await _loadHistory();
      if (!_isGeneralChat && target.progId != null) {
        await _refreshProgressSilently(provider);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _quizFeedback =
            'Error: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  Future<void> _explainWrongMcq(
    StudyProvider provider,

    AppStrings s,

    int qIdx,

    QuizQuestion q,

    int chosenIndex,
  ) async {
    final chosenText = (chosenIndex >= 0 && chosenIndex < q.options.length)
        ? q.options[chosenIndex]
        : '';

    final correctText =
        (q.correctIndex >= 0 && q.correctIndex < q.options.length)
        ? q.options[q.correctIndex]
        : '';

    _questionCtrl.text = s.isFr
        ? 'Pour Q${qIdx + 1} ("${q.question}"), j’ai choisi "$chosenText" au lieu de "$correctText". Explique-moi pourquoi c’est faux, pourquoi la bonne réponse fonctionne, et propose un exemple concret ou une simulation vidéo.'
        : 'For Q${qIdx + 1} ("${q.question}"), I picked "$chosenText" instead of "$correctText". Explain clearly why my choice is wrong, why the right answer works, and use a relatable example or visual video simulation.';

    await _askFollowUp(provider, s);
  }

  Future<void> _explainQuizMistakesSimpler(
    StudyProvider provider,

    AppStrings s,
  ) async {
    final missedDetails = <String>[];

    for (int i = 0; i < _quiz.length; i++) {
      final q = _quiz[i];

      if (q.isMcq) {
        final chosen = _selectedAnswers[i];

        if (chosen != null && chosen != q.correctIndex) {
          final picked = (chosen >= 0 && chosen < q.options.length)
              ? q.options[chosen]
              : '';

          missedDetails.add('Q${i + 1} ("${q.question}") -> chose "$picked"');
        }
      } else {
        final typed = _openAnswerCtrls[i]?.text.trim() ?? '';

        if (typed.isNotEmpty) {
          missedDetails.add('Q${i + 1} ("${q.question}") -> wrote "$typed"');
        }
      }
    }

    final contextSummary = missedDetails.isNotEmpty
        ? missedDetails.join('; ')
        : (_scoreSummary ?? 'recent quiz answers');

    _questionCtrl.text = s.isFr
        ? 'D’après mes réponses ($contextSummary), je n’ai pas encore bien compris. Ré-explique-moi simplement étape par étape comme à un élève qui débute, avec des exemples de mes loisirs et une simulation visuelle interactive.'
        : 'Based on my answers ($contextSummary), I still did not fully understand this lesson. Re-explain the weak parts in very simple step-by-step teacher language using my hobbies and an interactive visual simulation.';

    await _askFollowUp(provider, s);
  }

  Future<void> _sendComposerPrompt(StudyProvider provider, AppStrings s) async {
    if (_mode == AiMode.ask) {
      await _runAiAction(provider, s);
    } else {
      await _askFollowUp(provider, s);
    }
  }

  Future<void> _askFollowUp(StudyProvider provider, AppStrings s) async {
    final question = _questionCtrl.text.trim();

    final hasMedia = _attachedImages.isNotEmpty || _attachedAudio != null;

    if (question.isEmpty && !hasMedia) return;

    final target = _resolveSelectedTarget(provider.studentHome);

    final progId = target.progId;

    final targetMode = _mode;

    final displayPrompt = question.isNotEmpty
        ? question
        : (s.isFr ? 'Pièce jointe envoyée' : 'Attached file question');

    setState(() => _askLoading = true);

    try {
      late AiResponse res;

      if (hasMedia) {
        final mediaPayload = <({String name, List<int> bytes})>[
          ..._attachedImages.map((e) => (name: e.name, bytes: e.bytes)),

          if (_attachedAudio != null)
            (name: _attachedAudio!.name, bytes: _attachedAudio!.bytes),
        ];

        final chatHistoryPayload = _chatMessages
            .take(_chatMessages.length > 1 ? _chatMessages.length - 1 : 0)
            .where((m) => m.text.trim().isNotEmpty)
            .map((m) => {
                  'role': m.role == 'user' ? 'user' : 'model',
                  'content': m.text,
                })
            .toList();

        res = await provider.api.askTutorMultimodal(
          progressionId: progId,

          subjectName: target.subject,

          topicTitle: target.topic,

          question: question,

          mediaFiles: mediaPayload,

          conversationHistory: chatHistoryPayload,
        );
      } else {
        final chatHistoryPayload = _chatMessages
            .take(_chatMessages.length > 1 ? _chatMessages.length - 1 : 0)
            .where((m) => m.text.trim().isNotEmpty)
            .map((m) => {
                  'role': m.role == 'user' ? 'user' : 'model',
                  'content': m.text,
                })
            .toList();

        res = await provider.api.askTutor(
          progressionId: progId,

          subjectName: target.subject,

          topicTitle: target.topic,

          question: question,

          conversationHistory: chatHistoryPayload,
        );
      }

      if (!mounted) return;

      setState(() {
        final entry = (
          question: displayPrompt,

          answer: res.content,

          simulation: res.simulation,
        );

        if (targetMode == AiMode.summary) {
          _summaryFollowUps.add(entry);
        } else {
          _quizFollowUps.add(entry);
        }

        _questionCtrl.clear();

        _attachedImages.clear();

        _attachedAudio = null;
      });

      await _loadHistory();
      if (!_isGeneralChat && target.progId != null) {
        await _refreshProgressSilently(provider);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _askLoading = false);
    }
  }

  Future<void> _runAiAction(StudyProvider provider, AppStrings s) async {
    final target = _resolveSelectedTarget(provider.studentHome);

    final progId = target.progId;

    final hasCustom = (target.topic ?? '').isNotEmpty;

    if (_mode != AiMode.ask && progId == null && !hasCustom) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Choisissez d’abord une matière ou un sujet.'
                : 'Choose a subject or topic first.',
          ),
        ),
      );

      return;
    }

    final promptText = _questionCtrl.text.trim();

    final hasMedia = _attachedImages.isNotEmpty || _attachedAudio != null;

    if (_mode == AiMode.ask && promptText.isEmpty && !hasMedia) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Écrivez une question ou joignez une image / un audio.'
                : 'Enter a question or attach a picture / audio clip.',
          ),
        ),
      );

      return;
    }

    final activeMode = _mode;

    final effectiveQuestion = promptText.isNotEmpty
        ? promptText
        : (hasMedia
              ? (s.isFr
                    ? 'Veuillez examiner ce travail joint et me guider.'
                    : 'Please examine this attached work and guide me.')
              : 'Hello!');

    final mediaImagesToSubmit = List<({String name, Uint8List bytes})>.from(
      _attachedImages,
    );

    final mediaAudioToSubmit = _attachedAudio;

    setState(() {
      if (activeMode == AiMode.ask) {
        _askLoading = true;

        final userText = promptText.isNotEmpty
            ? promptText
            : (hasMedia ? (s.isFr ? '[Média joint]' : '[Attached Media]') : '');

        final userImgs = mediaImagesToSubmit.map((e) => e.bytes).toList();

        _chatMessages.add(
          _ChatMessage(role: 'user', text: userText, images: userImgs),
        );
        _syncPersistedChat();

        _questionCtrl.clear();

        _attachedImages.clear();

        _attachedAudio = null;

        _askOutput = null;

        _askModelUsed = null;

        _askSimulation = null;

        _scrollToBottom();
      } else if (activeMode == AiMode.summary) {
        _summaryLoading = true;

        _summaryOutput = null;

        _summaryModelUsed = null;

        _summarySources = [];

        _summaryDiagrams = [];

        _summarySimulation = null;
      } else {
        _quizLoading = true;

        _clearQuizState();
      }
    });

    try {
      late AiResponse res;

      if (activeMode == AiMode.ask) {
        final chatHistoryPayload = _chatMessages
            .take(_chatMessages.length > 1 ? _chatMessages.length - 1 : 0)
            .where((m) => m.text.trim().isNotEmpty)
            .map((m) => {
                  'role': m.role == 'user' ? 'user' : 'model',
                  'content': m.text,
                })
            .toList();

        if (hasMedia) {
          final mediaPayload = <({String name, List<int> bytes})>[
            ...mediaImagesToSubmit.map((e) => (name: e.name, bytes: e.bytes)),

            if (mediaAudioToSubmit != null)
              (name: mediaAudioToSubmit.name, bytes: mediaAudioToSubmit.bytes),
          ];

          res = await provider.api.askTutorMultimodal(
            progressionId: target.progId,

            subjectName: target.subject,

            topicTitle: target.topic,

            question: effectiveQuestion,

            mediaFiles: mediaPayload,

            conversationHistory: chatHistoryPayload,
          );
        } else {
          res = await provider.api.askTutor(
            progressionId: target.progId,

            subjectName: target.subject,

            topicTitle: target.topic,

            question: effectiveQuestion,

            conversationHistory: chatHistoryPayload,
          );
        }
      } else if (activeMode == AiMode.summary) {
        res = await provider.api.summarizeTopic(
          progressionId: progId,

          subjectName: target.subject,

          topicTitle: target.topic,
        );
      } else {
        res = await provider.api.generateQuiz(
          progressionId: progId,

          subjectName: target.subject,

          topicTitle: target.topic,

          numQuestions: 5,
        );
      }

      if (!mounted) return;

      setState(() {
        if (activeMode == AiMode.ask) {
          _chatMessages.add(
            _ChatMessage(
              role: 'assistant',

              text: res.content,

              simulation: res.simulation,

              modelUsed: res.modelUsed,
            ),
          );

          _askOutput = res.content;

          _askModelUsed = res.modelUsed;

          _askSimulation = res.simulation;

          _attachedImages.clear();

          _attachedAudio = null;

          _scrollToBottom();
          _syncPersistedChat();
        } else if (activeMode == AiMode.summary) {
          _summaryOutput = res.content;

          _summaryModelUsed = res.modelUsed;

          _summarySources = res.sources;

          _summaryDiagrams = res.diagrams;

          _summarySimulation = res.simulation;

          final cacheKey =
              "${target.progId ?? target.topic}_${provider.languageCode}";

          _summaryByLang[cacheKey] = (
            content: res.content,

            diagrams: res.diagrams,

            sources: res.sources,

            modelUsed: res.modelUsed,

            simulation: res.simulation,
          );
        } else {
          _quiz = res.quiz ?? [];

          _quizModelUsed = res.modelUsed;

          final cacheKey =
              "${target.progId ?? target.topic}_${provider.languageCode}";

          _quizByLang[cacheKey] = (quiz: _quiz, modelUsed: res.modelUsed);
        }
      });

      await _loadHistory();
      if (!_isGeneralChat && target.progId != null) {
        await _refreshProgressSilently(provider);
      }
    } catch (e) {
      if (!mounted) return;

      final rawErr = e.toString();

      final isConnErr =
          rawErr.contains('Socket') ||
          rawErr.contains('No route to host') ||
          rawErr.contains('Connection refused') ||
          rawErr.contains('ClientException') ||
          rawErr.contains('TimeoutException');

      final err = isConnErr
          ? (s.isFr
                ? 'Impossible de joindre le serveur. Assurez-vous que votre téléphone est connecté au même réseau Wi-Fi que votre ordinateur.'
                : 'Cannot reach server. Please ensure your phone is connected to the same Wi-Fi network as your computer.')
          : 'Error: ${rawErr.replaceFirst('Exception: ', '')}';

      setState(() {
        if (activeMode == AiMode.ask) {
          _chatMessages.add(_ChatMessage(role: 'assistant', text: err));

          _askOutput = err;

          _scrollToBottom();
          _syncPersistedChat();
        } else if (activeMode == AiMode.summary) {
          _summaryOutput = err;
        } else {
          _quizFeedback = err;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (activeMode == AiMode.ask) _askLoading = false;

          if (activeMode == AiMode.summary) _summaryLoading = false;

          if (activeMode == AiMode.quiz) _quizLoading = false;
        });
      }
    }
  }

  String _formatHistoryDate(DateTime? dt, bool isFr) {
    if (dt == null) return isFr ? "Aujourd'hui" : 'Today';

    final local = dt.toLocal();

    final now = DateTime.now();

    final isToday =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    final yesterday = now.subtract(const Duration(days: 1));

    final isYesterday =
        local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;

    final hh = local.hour.toString().padLeft(2, '0');

    final mm = local.minute.toString().padLeft(2, '0');

    if (isToday) {
      return isFr ? "Aujourd'hui à $hh:$mm" : 'Today at $hh:$mm';
    } else if (isYesterday) {
      return isFr ? 'Hier à $hh:$mm' : 'Yesterday at $hh:$mm';
    }

    const monthsFr = [
      'janv.',

      'févr.',

      'mars',

      'avr.',

      'mai',

      'juin',

      'juil.',

      'août',

      'sept.',

      'oct.',

      'nov.',

      'déc.',
    ];

    const monthsEn = [
      'Jan',

      'Feb',

      'Mar',

      'Apr',

      'May',

      'Jun',

      'Jul',

      'Aug',

      'Sep',

      'Oct',

      'Nov',

      'Dec',
    ];

    final m = isFr ? monthsFr[local.month - 1] : monthsEn[local.month - 1];

    return '${local.day} $m ${local.year} · $hh:$mm';
  }

  Future<void> _deleteHistoryItem(AiHistoryItem item, AppStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,

      builder: (ctx) => AlertDialog(
        title: Text(s.isFr ? 'Supprimer cet élément ?' : 'Delete this item?'),

        content: Text(
          s.isFr
              ? 'Voulez-vous vraiment supprimer cette recherche de votre historique ?'
              : 'Are you sure you want to delete this research from your history?',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),

            child: Text(s.cancel),
          ),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),

            onPressed: () => Navigator.pop(ctx, true),

            child: Text(s.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final provider = context.read<StudyProvider>();

    final ok = await provider.api.deleteAiHistoryItem(item.id);

    if (ok && mounted) {
      setState(() {
        _history.removeWhere((h) => h.id == item.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Élément supprimé de l\'historique.'
                : 'Item deleted from history.',
          ),

          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAllHistory(AppStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,

      builder: (ctx) => AlertDialog(
        title: Text(
          s.isFr ? 'Vider tout l\'historique ?' : 'Clear all history?',
        ),

        content: Text(
          s.isFr
              ? 'Cette action supprimera toutes vos recherches et résumés IA enregistrés.'
              : 'This will delete all your saved AI research, summaries, and quizzes.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),

            child: Text(s.cancel),
          ),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),

            onPressed: () => Navigator.pop(ctx, true),

            child: Text(
              s.isFr ? 'Tout vider' : 'Clear All',

              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final provider = context.read<StudyProvider>();

    final ok = await provider.api.clearAiHistory();

    if (ok && mounted) {
      setState(() {
        _history.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isFr
                ? 'Historique entièrement vidé.'
                : 'History completely cleared.',
          ),

          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isLikelyFrench(String text) {
    final lower = ' ${text.toLowerCase()} ';
    final frMarkers = [
      ' quel ', ' quelle ', ' quels ', ' quelles ', ' est-ce ', ' traité ',
      ' guerre ', ' mondiale ', ' pourquoi ', ' selon ', ' dans ', ' avec ',
      ' pour ', ' cette ', ' sont ', ' était ', ' étape ', ' le ', ' la ',
      ' les ', ' des ', ' du ', ' un ', ' une ', ' en ', ' au ', ' aux '
    ];
    int count = 0;
    for (final w in frMarkers) {
      if (lower.contains(w)) count++;
    }
    return count >= 2;
  }

  bool _isLikelyEnglish(String text) {
    final lower = ' ${text.toLowerCase()} ';
    final enMarkers = [
      ' which ', ' what ', ' why ', ' how ', ' where ', ' treaty ', ' war ',
      ' world ', ' the ', ' this ', ' that ', ' with ', ' from ', ' have ',
      ' been ', ' step ', ' explain ', ' answer ', ' questions '
    ];
    int count = 0;
    for (final w in enMarkers) {
      if (lower.contains(w)) count++;
    }
    return count >= 2;
  }

  bool _autoTranslatingQuiz = false;
  Future<void> _autoTranslateQuizIfNeeded(StudyProvider provider) async {
    if (_autoTranslatingQuiz || _quiz.isEmpty || _quizLoading) return;
    final currentLang = provider.languageCode;
    final sample = _quiz.map((q) => q.question).join(' ');
    final isWrongLang = (currentLang == 'en' && _isLikelyFrench(sample)) ||
        (currentLang == 'fr' && _isLikelyEnglish(sample));
    if (!isWrongLang) return;

    final target = _resolveSelectedTarget(provider.studentHome);
    final keyBase = "${target.progId ?? target.topic}";
    final quizKey = "${keyBase}_$currentLang";

    if (_quizByLang.containsKey(quizKey)) {
      setState(() {
        _quiz = _quizByLang[quizKey]!.quiz;
        _quizModelUsed = _quizByLang[quizKey]!.modelUsed;
      });
      return;
    }

    _autoTranslatingQuiz = true;
    setState(() => _quizLoading = true);
    try {
      final translatedList = await provider.api.translateQuiz(
        quiz: _quiz,
        targetLanguage: currentLang,
      );
      if (mounted) {
        setState(() {
          _quiz = translatedList;
          _quizByLang[quizKey] = (quiz: translatedList, modelUsed: _quizModelUsed);
          _quizLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _quizLoading = false);
    } finally {
      _autoTranslatingQuiz = false;
    }
  }

  bool _autoTranslatingSummary = false;
  Future<void> _autoTranslateSummaryIfNeeded(StudyProvider provider) async {
    if (_autoTranslatingSummary || _summaryOutput == null || _summaryOutput!.trim().isEmpty || _summaryLoading) return;
    final currentLang = provider.languageCode;
    final text = _summaryOutput!;
    final isWrongLang = (currentLang == 'en' && _isLikelyFrench(text)) ||
        (currentLang == 'fr' && _isLikelyEnglish(text));
    if (!isWrongLang) return;

    final target = _resolveSelectedTarget(provider.studentHome);
    final keyBase = "${target.progId ?? target.topic}";
    final summaryKey = "${keyBase}_$currentLang";

    if (_summaryByLang.containsKey(summaryKey)) {
      final cached = _summaryByLang[summaryKey]!;
      setState(() {
        _summaryOutput = cached.content;
        _summaryDiagrams = cached.diagrams;
        _summarySources = cached.sources;
        _summaryModelUsed = cached.modelUsed;
        _summarySimulation = cached.simulation;
      });
      return;
    }

    _autoTranslatingSummary = true;
    setState(() => _summaryLoading = true);
    try {
      final translated = await provider.api.translateText(
        text: text,
        targetLanguage: currentLang,
      );
      if (mounted) {
        final isFr = currentLang == 'fr';
        setState(() {
          _summaryOutput = cleanMathNotation(translated, '', isFr);
          _summarySimulation = provider.api.buildSimulation(
            target.topic ?? '',
            target.subject ?? '',
            isFr,
          );
          _summaryLoading = false;
          _summaryByLang[summaryKey] = (
            content: _summaryOutput!,
            diagrams: _summaryDiagrams,
            sources: _summarySources,
            modelUsed: _summaryModelUsed ?? 'gemini-flash-lite-latest',
            simulation: _summarySimulation,
          );
        });
      }
    } catch (_) {
      if (mounted) setState(() => _summaryLoading = false);
    } finally {
      _autoTranslatingSummary = false;
    }
  }

  Future<void> _handleLanguageChange(
    StudyProvider provider,
    String targetLang,
  ) async {
    final s = AppStrings(targetLang);
    final target = _resolveSelectedTarget(provider.studentHome);
    final keyBase = "${target.progId ?? target.topic}";
    final isFr = targetLang == 'fr';

    // 1. Instantly translate active chat messages if any exist in parallel
    if (_chatMessages.isNotEmpty) {
      setState(() => _askLoading = true);
      try {
        final futures = _chatMessages.map((m) async {
          if (m.text.trim().isEmpty) return m;
          try {
            final translated = await provider.api.translateText(
              text: m.text,
              targetLanguage: targetLang,
            );
            return _ChatMessage(
              role: m.role,
              text: cleanMathNotation(translated, '', isFr),
              images: m.images,
              simulation: m.simulation != null
                  ? provider.api.buildSimulation(
                      target.topic ?? '',
                      target.subject ?? '',
                      isFr,
                    )
                  : null,
              modelUsed: m.modelUsed,
              timestamp: m.timestamp,
            );
          } catch (_) {
            return m;
          }
        });
        final updated = await Future.wait(futures);
        if (mounted) {
          setState(() {
            _chatMessages.clear();
            _chatMessages.addAll(updated);
            _syncPersistedChat();
            _askLoading = false;
          });
          _scrollToBottom();
        }
      } catch (_) {
        if (mounted) setState(() => _askLoading = false);
      }
    }

    // 2. Translate or update active Summary
    if (_mode == AiMode.summary || _summaryOutput != null) {
      final summaryKey = "${keyBase}_$targetLang";

      if (_summaryByLang.containsKey(summaryKey)) {
        final cached = _summaryByLang[summaryKey]!;
        setState(() {
          _summaryOutput = cached.content;
          _summaryDiagrams = cached.diagrams;
          _summarySources = cached.sources;
          _summaryModelUsed = cached.modelUsed;
          _summarySimulation = cached.simulation;
        });
      } else if (_summaryOutput != null && _summaryOutput!.trim().isNotEmpty) {
        setState(() => _summaryLoading = true);
        try {
          final translated = await provider.api.translateText(
            text: _summaryOutput!,
            targetLanguage: targetLang,
          );
          if (mounted) {
            setState(() {
              _summaryOutput = cleanMathNotation(translated, '', isFr);
              _summarySimulation = provider.api.buildSimulation(
                target.topic ?? '',
                target.subject ?? '',
                isFr,
              );
              _summaryLoading = false;
              _summaryByLang[summaryKey] = (
                content: _summaryOutput!,
                diagrams: _summaryDiagrams,
                sources: _summarySources,
                modelUsed: _summaryModelUsed ?? 'gemini-flash-lite-latest',
                simulation: _summarySimulation,
              );
            });
          }
        } catch (_) {
          if (mounted) setState(() => _summaryLoading = false);
        }
      } else if (!_isGeneralChat) {
        _runAiAction(provider, s);
      }
    }

    // 3. Translate or update active Quiz
    if (_quiz.isNotEmpty) {
      final quizKey = "${keyBase}_$targetLang";
      if (_quizByLang.containsKey(quizKey)) {
        final cached = _quizByLang[quizKey]!;
        setState(() {
          _quiz = cached.quiz;
          _quizModelUsed = cached.modelUsed;
        });
      } else {
        setState(() => _quizLoading = true);
        try {
          final translatedList = await provider.api.translateQuiz(
            quiz: _quiz,
            targetLanguage: targetLang,
          );
          if (mounted) {
            setState(() {
              _quiz = translatedList;
              _quizByLang[quizKey] = (
                quiz: translatedList,
                modelUsed: _quizModelUsed,
              );
              _quizLoading = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _quizLoading = false);
        }
      }
    } else if (_mode == AiMode.quiz && !_isGeneralChat) {
      _runAiAction(provider, s);
    }
  }

  Widget _buildHistoryDrawer(AppStrings s) {
    final query = _historyQuery.trim().toLowerCase();

    final filtered = query.isEmpty
        ? _history
        : _history
              .where(
                (h) =>
                    h.prompt.toLowerCase().contains(query) ||
                    (h.subjectName ?? '').toLowerCase().contains(query) ||
                    (h.topicTitle ?? '').toLowerCase().contains(query),
              )
              .toList();

    return Drawer(
      width: MediaQuery.of(context).size.width.clamp(315.0, 370.0),

      backgroundColor: Colors.white,

      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 14, 10, 14),

              decoration: const BoxDecoration(color: _deepNavy),

              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),

                    tooltip: s.isFr ? 'Retour' : 'Back',

                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  const SizedBox(width: 4),

                  const Icon(Icons.history_rounded, color: Colors.white),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      s.aiHistoryTitle,

                      style: const TextStyle(
                        color: Colors.white,

                        fontSize: 17,

                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),

                    tooltip: s.refresh,

                    onPressed: _loadHistory,
                  ),

                  if (_history.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_sweep_outlined,

                        color: Colors.white,
                      ),

                      tooltip: s.isFr ? 'Tout vider' : 'Clear all',

                      onPressed: () => _clearAllHistory(s),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),

              child: TextField(
                controller: _historySearchCtrl,

                onChanged: (v) => setState(() => _historyQuery = v),

                decoration: InputDecoration(
                  hintText: s.aiSearchHistoryHint,

                  prefixIcon: const Icon(Icons.search, size: 20),

                  isDense: true,

                  filled: true,

                  fillColor: const Color(0xFFF1F5F9),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),

                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            Builder(
              builder: (context) {
                final groupedFiltered = <({AiHistoryItem item, int count})>[];
                for (final it in filtered) {
                  if (it.interactionType == 'chat') {
                    final existingIdx = groupedFiltered.indexWhere(
                      (g) => g.item.interactionType == 'chat' && _sameHistoryLesson(g.item, it),
                    );
                    if (existingIdx >= 0) {
                      groupedFiltered[existingIdx] = (
                        item: groupedFiltered[existingIdx].item,
                        count: groupedFiltered[existingIdx].count + 1,
                      );
                      continue;
                    }
                  }
                  groupedFiltered.add((item: it, count: 1));
                }

                return Expanded(
                  child: _historyLoading
                      ? const Center(child: CircularProgressIndicator())
                      : groupedFiltered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              s.aiNoHistory,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: groupedFiltered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (ctx, i) {
                            final entry = groupedFiltered[i];
                            final item = entry.item;
                            final count = entry.count;

                            final IconData leadingIcon;
                            final Color badgeColor;

                            if (item.interactionType == 'quiz') {
                              leadingIcon = Icons.quiz_outlined;
                              badgeColor = _primaryBlue;
                            } else if (item.interactionType == 'summary') {
                              leadingIcon = Icons.summarize_outlined;
                              badgeColor = const Color(0xFF10B981);
                            } else {
                              leadingIcon = Icons.auto_awesome;
                              badgeColor = _aiPurple;
                            }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,

                            vertical: 2,
                          ),

                          tileColor: const Color(0xFFF8FAFC),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),

                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),

                          leading: CircleAvatar(
                            radius: 18,

                            backgroundColor: badgeColor.withAlpha(28),

                            child: Icon(
                              leadingIcon,

                              size: 18,

                              color: badgeColor,
                            ),
                          ),

                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Wrap(
                                spacing: 6,

                                runSpacing: 4,

                                crossAxisAlignment: WrapCrossAlignment.center,

                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2F6),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFCBD5E1),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 10,
                                          color: Color(0xFF475569),
                                        ),
                                        const SizedBox(width: 3.5),
                                        Text(
                                          _formatHistoryDate(
                                            item.createdAt,
                                            s.isFr,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (count > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _aiPurple.withAlpha(22),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _aiPurple.withAlpha(50),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        s.isFr
                                            ? '$count échanges'
                                            : '$count messages',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _aiPurple,
                                        ),
                                      ),
                                    ),

                                  if (item.subjectName != null &&
                                      item.subjectName!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,

                                        vertical: 2,
                                      ),

                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),

                                        borderRadius: BorderRadius.circular(6),
                                      ),

                                      child: Text(
                                        item.subjectName!,

                                        maxLines: 1,

                                        overflow: TextOverflow.ellipsis,

                                        style: const TextStyle(
                                          fontSize: 10.5,

                                          fontWeight: FontWeight.w600,

                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                ],
                              ),

                              const SizedBox(height: 5),

                              Text(
                                item.prompt,

                                maxLines: 2,

                                overflow: TextOverflow.ellipsis,

                                style: const TextStyle(
                                  fontSize: 13.5,

                                  fontWeight: FontWeight.w600,

                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),

                          subtitle:
                              (item.topicTitle != null &&
                                  item.topicTitle!.isNotEmpty)
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 3),

                                  child: Text(
                                    item.topicTitle!,

                                    maxLines: 1,

                                    overflow: TextOverflow.ellipsis,

                                    style: const TextStyle(
                                      fontSize: 11.5,

                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                )
                              : null,

                          trailing: IconButton(
                            padding: EdgeInsets.zero,

                            constraints: const BoxConstraints(),

                            icon: const Icon(
                              Icons.delete_outline,

                              size: 20,

                              color: Color(0xFFEF4444),
                            ),

                            tooltip: s.delete,

                            onPressed: () => _deleteHistoryItem(item, s),
                          ),

                          onTap: () => _loadHistoryItem(item),
                        );
                      },
                    ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsPreview() {
    if (_attachedImages.isEmpty && _attachedAudio == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),

      child: Wrap(
        spacing: 8,

        runSpacing: 8,

        crossAxisAlignment: WrapCrossAlignment.center,

        children: [
          ...List.generate(_attachedImages.length, (idx) {
            final img = _attachedImages[idx];

            return Stack(
              clipBehavior: Clip.none,

              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),

                  child: Image.memory(
                    img.bytes,

                    width: 68,

                    height: 68,

                    fit: BoxFit.cover,

                    errorBuilder: (_, _, _) => Container(
                      width: 68,

                      height: 68,

                      color: const Color(0xFFE2E8F0),

                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),

                Positioned(
                  top: -6,

                  right: -6,

                  child: InkWell(
                    onTap: () => setState(() => _attachedImages.removeAt(idx)),

                    child: Container(
                      padding: const EdgeInsets.all(3),

                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),

                        shape: BoxShape.circle,
                      ),

                      child: const Icon(
                        Icons.close,

                        size: 13,

                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),

          if (_attachedAudio != null)
            Chip(
              avatar: const Icon(Icons.graphic_eq, color: _aiPurple, size: 18),

              label: Text(
                '${_attachedAudio!.name} (${(_attachedAudio!.bytes.length / 1024).ceil()} KB)',

                overflow: TextOverflow.ellipsis,
              ),

              deleteIcon: const Icon(Icons.close, size: 16),

              onDeleted: () => setState(() => _attachedAudio = null),

              backgroundColor: const Color(0xFFF3E8FF),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingWaveform() {
    return SizedBox(
      height: 28,

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,

        children: _voiceLevels.map((lvl) {
          final h = (4 + (lvl * 20)).clamp(3.0, 24.0);

          return Container(
            width: 3,

            height: h,

            decoration: BoxDecoration(
              color: const Color(0xFF64748B),

              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildComposerPill(StudyProvider provider, AppStrings s) {
    final canSend =
        _questionCtrl.text.trim().isNotEmpty ||
        _attachedImages.isNotEmpty ||
        _attachedAudio != null;

    if (_recording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(30),

          border: Border.all(color: const Color(0xFFE2E8F0)),

          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),

              blurRadius: 12,

              offset: Offset(0, 4),
            ),
          ],
        ),

        child: Row(
          children: [
            Material(
              color: const Color(0xFFF8FAFC),

              shape: const CircleBorder(
                side: BorderSide(color: Color(0xFFE2E8F0)),
              ),

              child: InkWell(
                customBorder: const CircleBorder(),

                onTap: _cancelVoiceRecording,

                child: const Padding(
                  padding: EdgeInsets.all(9),

                  child: Icon(
                    Icons.close_rounded,

                    color: Color(0xFF0F172A),

                    size: 19,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            Expanded(child: _buildRecordingWaveform()),

            const SizedBox(width: 8),

            Material(
              color: const Color(0xFFF8FAFC),

              shape: const CircleBorder(
                side: BorderSide(color: Color(0xFFE2E8F0)),
              ),

              child: InkWell(
                customBorder: const CircleBorder(),

                onTap: () =>
                    _finishVoiceRecording(provider, s, autoSend: false),

                child: const Padding(
                  padding: EdgeInsets.all(9),

                  child: Icon(
                    Icons.stop_rounded,

                    color: Color(0xFF0F172A),

                    size: 19,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            Material(
              color: _primaryBlue,

              shape: const CircleBorder(),

              child: InkWell(
                customBorder: const CircleBorder(),

                onTap: () => _finishVoiceRecording(provider, s, autoSend: true),

                child: const Padding(
                  padding: EdgeInsets.all(9),

                  child: Icon(
                    Icons.arrow_upward_rounded,

                    color: Colors.white,

                    size: 19,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(30),

        border: Border.all(color: const Color(0xFFE2E8F0)),

        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),

            blurRadius: 12,

            offset: Offset(0, 4),
          ),
        ],
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,

        children: [
          IconButton(
            onPressed: (_loading || _transcribing) ? null : _pickImages,

            tooltip: s.aiAttachPicture,

            icon: const Icon(
              Icons.add_rounded,

              size: 24,

              color: Color(0xFF0F172A),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),

              child: TextField(
                controller: _questionCtrl,

                enabled: !_transcribing,

                style: const TextStyle(
                  color: Color(0xFF0F172A),

                  fontSize: 14.5,

                  fontWeight: FontWeight.w600,
                ),

                minLines: 1,

                maxLines: 4,

                textInputAction: TextInputAction.send,

                onChanged: (_) => setState(() {}),

                onSubmitted: (_) {
                  if (canSend && !_loading && !_transcribing) {
                    _sendComposerPrompt(provider, s);
                  }
                },

                decoration: InputDecoration(
                  hintText: _transcribing
                      ? (s.isFr ? 'Transcription...' : 'Transcribing...')
                      : _mode == AiMode.summary
                      ? (s.isFr
                            ? 'Pas compris un point du résumé ? Demandez ici...'
                            : 'Ask about anything unclear in these notes...')
                      : _mode == AiMode.quiz
                      ? (s.isFr
                            ? 'Demander pourquoi une réponse est vraie ou fausse...'
                            : 'Ask why an answer is right/wrong or for an example...')
                      : (s.isFr ? 'Demander à Kivora...' : 'Ask Kivora...'),

                  hintStyle: const TextStyle(
                    color: Color(0xFF475569),

                    fontSize: 14.5,

                    fontWeight: FontWeight.w500,
                  ),

                  border: InputBorder.none,

                  isDense: true,

                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
          ),

          IconButton(
            onPressed: (_loading || _transcribing)
                ? null
                : () => _startVoiceRecording(s),

            tooltip: s.aiRecordVoice,

            icon: const Icon(
              Icons.mic_none_rounded,

              color: Color(0xFF334155),

              size: 23,
            ),
          ),

          const SizedBox(width: 2),

          Material(
            color: (_loading || _transcribing)
                ? const Color(0xFF93C5FD)
                : (canSend ? _deepNavy : _primaryBlue),

            shape: const CircleBorder(),

            child: InkWell(
              customBorder: const CircleBorder(),

              onTap: (_loading || _transcribing)
                  ? null
                  : (canSend
                        ? () => _sendComposerPrompt(provider, s)
                        : _pickAudioFile),

              child: Padding(
                padding: const EdgeInsets.all(10),

                child: (_loading || _transcribing)
                    ? const SizedBox(
                        width: 20,

                        height: 20,

                        child: CircularProgressIndicator(
                          strokeWidth: 2,

                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        canSend
                            ? Icons.arrow_upward_rounded
                            : Icons.graphic_eq_rounded,

                        color: Colors.white,

                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SimulationData _fallbackSimulation(String content, bool isFr) {
    final clean = content
        .replaceAll(RegExp(r'===SIMULATION_JSON===[\s\S]*'), '')
        .replaceAll(RegExp(r'[#*_`>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final rawLines = content
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[#*_`>|]+'), '').trim())
        .where((l) => l.length > 3)
        .toList();
    final title = rawLines.isNotEmpty
        ? rawLines.first
        : (isFr ? 'Explication du cours' : 'Lesson explainer');
    final sentences = clean
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.length > 40 && e.length < 260)
        .toList();
    String pick(int i, String d) => i < sentences.length ? sentences[i] : d;
    final n = sentences.length;
    return SimulationData(
      title: title.length > 90 ? title.substring(0, 90) : title,
      scenario: pick(0, title),
      keyTakeaway: pick(n > 3 ? n - 1 : 2, title),
      steps: [
        SimulationStep(
          stepNumber: 1,
          title: isFr ? 'Idée centrale' : 'Core Concept',
          action: pick(0, title),
          outcome: isFr ? 'Comprendre la notion' : 'Understand the idea',
        ),
        SimulationStep(
          stepNumber: 2,
          title: isFr ? 'Mécanisme et règle' : 'Mechanism & Rule',
          action: pick(n > 4 ? n ~/ 2 : 1, title),
          outcome: isFr ? 'Voir comment cela fonctionne' : 'See how it works',
        ),
        SimulationStep(
          stepNumber: 3,
          title: isFr ? 'Maîtrise' : 'Mastery',
          action: pick(n > 3 ? n - 1 : 2, title),
          outcome: isFr ? 'Retenir l\u2019essentiel' : 'Retain the essentials',
        ),
      ],
    );
  }

  Widget _buildSimulationPlayer(SimulationData sim, AppStrings s) {
    return AiVideoExplainerPlayer(simulation: sim, isFr: s.isFr);
  }

  Widget _buildLinksCard({
    required String title,

    required List<Map<String, String>> items,

    required IconData icon,

    required Color accentColor,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const SizedBox(height: 12),

        const Divider(height: 1),

        const SizedBox(height: 10),

        Row(
          children: [
            Icon(icon, size: 17, color: accentColor),

            const SizedBox(width: 6),

            Expanded(
              child: Text(
                title,

                style: const TextStyle(
                  fontWeight: FontWeight.w800,

                  fontSize: 13,

                  color: _deepNavy,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        ...items.asMap().entries.map((entry) {
          final idx = entry.key + 1;

          final item = entry.value;

          final url = (item['url'] ?? '').trim();

          final uri = Uri.tryParse(url);

          final validUri =
              uri != null && (uri.isScheme('http') || uri.isScheme('https'))
              ? uri
              : null;

          final sourceName = (item['source'] ?? item['provider'] ?? '').trim();

          final headline = (item['title'] ?? '').trim();

          final snippet = (item['snippet'] ?? item['reason'] ?? '').trim();

          final imageUrl = (item['image_url'] ?? '').trim();

          final imageUri = Uri.tryParse(imageUrl);

          final hasImage =
              imageUri != null &&
              (imageUri.isScheme('http') || imageUri.isScheme('https'));

          void handleOpen() {
            if (validUri != null) {
              openExternalUrl(url);
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),

            child: MouseRegion(
              cursor: validUri != null
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,

              child: Material(
                color: const Color(0xFFF8FAFC),

                borderRadius: BorderRadius.circular(10),

                child: InkWell(
                  borderRadius: BorderRadius.circular(10),

                  onTap: validUri != null ? handleOpen : null,

                  child: Container(
                    padding: const EdgeInsets.all(10),

                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),

                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),

                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        if (hasImage)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),

                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),

                              child: Image.network(
                                imageUrl,

                                width: 64,

                                height: 64,

                                fit: BoxFit.cover,

                                errorBuilder: (context, error, stackTrace) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                sourceName.isNotEmpty
                                    ? '[Source $idx] $headline · $sourceName'
                                    : '[Source $idx] $headline',

                                style: TextStyle(
                                  fontWeight: FontWeight.w700,

                                  fontSize: 12.5,

                                  color: accentColor,
                                ),
                              ),

                              if (snippet.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),

                                  child: Text(
                                    snippet,

                                    maxLines: 2,

                                    overflow: TextOverflow.ellipsis,

                                    style: const TextStyle(
                                      fontSize: 11.5,

                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),

                              if (url.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),

                                  child: Text(
                                    url,

                                    maxLines: 1,

                                    overflow: TextOverflow.ellipsis,

                                    style: const TextStyle(
                                      fontSize: 11,

                                      color: Color(0xFF2563EB),

                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        if (validUri != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),

                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,

                                vertical: 5,
                              ),

                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.10),

                                borderRadius: BorderRadius.circular(999),

                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.25),
                                ),
                              ),

                              child: Row(
                                mainAxisSize: MainAxisSize.min,

                                children: [
                                  Text(
                                    'Open',

                                    style: TextStyle(
                                      fontSize: 11,

                                      fontWeight: FontWeight.w700,

                                      color: accentColor,
                                    ),
                                  ),

                                  const SizedBox(width: 3),

                                  Icon(
                                    Icons.open_in_new_rounded,

                                    size: 13,

                                    color: accentColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFollowUpsSection(
    List<({String question, String answer, SimulationData? simulation})>
    followUps,

    AppStrings s,
  ) {
    if (followUps.isEmpty) return const SizedBox.shrink();

    final studentName = context.read<StudyProvider>().user?.fullName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const SizedBox(height: 12),

        ...followUps.map(
          (item) => Card(
            color: Colors.white,

            margin: const EdgeInsets.only(bottom: 10),

            child: Padding(
              padding: const EdgeInsets.all(14),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,

                      vertical: 8,
                    ),

                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),

                      borderRadius: BorderRadius.circular(10),
                    ),

                    child: Text(
                      item.question,

                      style: const TextStyle(
                        fontWeight: FontWeight.w700,

                        fontSize: 13,

                        color: _deepNavy,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TeacherNotesView(
                    content: item.answer,

                    isFr: s.isFr,

                    studentName: studentName,
                  ),

                  if (item.simulation != null &&
                      item.simulation!.steps.isNotEmpty) ...[
                    const SizedBox(height: 10),

                    AiVideoExplainerPlayer(
                      simulation: item.simulation!,

                      isFr: s.isFr,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressStatusBar(
    StudyProvider provider,

    AppStrings s,

    int? progId,
  ) {
    if (progId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),

      child: Wrap(
        spacing: 8,

        runSpacing: 6,

        children: [
          ActionChip(
            avatar: const Icon(
              Icons.check_circle_outline_rounded,

              size: 17,

              color: Color(0xFF047857),
            ),

            backgroundColor: const Color(0xFFECFDF5),

            label: Text(
              s.isFr ? 'Bien compris (Maîtrisé)' : 'Mark Understood',

              style: const TextStyle(
                color: Color(0xFF065F46),

                fontWeight: FontWeight.w700,

                fontSize: 12,
              ),
            ),

            onPressed: () => _markUnderstanding(
              provider,

              s,

              progId,

              status: 'understood',

              understandingLevel: 'full',
            ),
          ),

          ActionChip(
            avatar: const Icon(
              Icons.replay_circle_filled_outlined,

              size: 17,

              color: Color(0xFFD97706),
            ),

            backgroundColor: const Color(0xFFFFFBEB),

            label: Text(
              s.isFr ? 'À réviser encore' : 'Needs Revision',

              style: const TextStyle(
                color: Color(0xFF92400E),

                fontWeight: FontWeight.w700,

                fontSize: 12,
              ),
            ),

            onPressed: () => _markUnderstanding(
              provider,

              s,

              progId,

              status: 'needs_revision',

              understandingLevel: 'partial',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();

    final s = AppStrings(provider.languageCode);

    final currentLang = provider.languageCode;

    _activeLanguage = currentLang;

    final topics = _combinedCurriculumTopics(provider.studentHome);

    final hasCustom = _customTopic != null && _customTopic!.isNotEmpty;

    final effectiveId = (_isGeneralChat || hasCustom)
        ? null
        : (topics.any((t) => t.id == _selectedProgressionId)
              ? _selectedProgressionId
              : (topics.isNotEmpty ? topics.first.id : null));

    return Scaffold(
      key: _scaffoldKey,

      backgroundColor: Colors.transparent,

      drawer: _buildHistoryDrawer(s),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),

            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu_rounded, color: _deepNavy),

                  tooltip: s.aiHistoryTitle,

                  onPressed: _openHistoryDrawer,
                ),

                if (_isGeneralChat) ...[
                  const SizedBox(width: 6),

                  InkWell(
                    onTap: () {
                      final topics = _combinedCurriculumTopics(
                        provider.studentHome,
                      );

                      setState(() {
                        _isGeneralChat = false;

                        _mode = AiMode.summary;

                        _resetTopicWorkspace();

                        if ((_selectedProgressionId == null ||
                                !topics.any(
                                  (t) => t.id == _selectedProgressionId,
                                )) &&
                            topics.isNotEmpty) {
                          _selectedProgressionId = topics.first.id;
                        }
                      });

                      if (_selectedProgressionId != null) {
                        _runAiAction(provider, s);
                      }
                    },

                    borderRadius: BorderRadius.circular(20),

                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),

                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(20),

                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),

                      child: Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            size: 16,
                            color: _primaryBlue,
                          ),

                          const SizedBox(width: 6),

                          Text(
                            s.isFr ? 'Sujets de cours' : 'Curriculum Topics',

                            style: const TextStyle(
                              fontSize: 12.5,

                              fontWeight: FontWeight.w700,

                              color: _primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                IconButton(
                  onPressed: _startNewSearch,

                  tooltip: s.aiNewChat,

                  icon: const Icon(
                    Icons.add_comment_outlined,

                    color: _deepNavy,

                    size: 21,
                  ),
                ),
              ],
            ),
          ),

          if (!_isGeneralChat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),

              child: Column(
                children: [
                  if (hasCustom)
                    Card(
                      color: const Color(0xFFEFF6FF),

                      margin: const EdgeInsets.only(bottom: 10),

                      child: ListTile(
                        dense: true,

                        leading: const Icon(
                          Icons.auto_awesome,

                          color: _primaryBlue,
                        ),

                        title: Text(
                          localizeTopicTitle(_customTopic!, s.isFr),

                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),

                        subtitle: Text(
                          _customSubject != null
                              ? localizeSubject(_customSubject!, s.isFr)
                              : (s.isFr ? 'Étude indépendante' : 'Independent Study'),
                        ),

                        trailing: topics.isNotEmpty
                            ? TextButton(
                                onPressed: () => setState(() {
                                  _customSubject = null;

                                  _customTopic = null;

                                  _selectedProgressionId = topics.first.id;

                                  _resetTopicWorkspace();
                                }),

                                child: Text(s.isFr ? 'Changer' : 'Switch'),
                              )
                            : null,
                      ),
                    )
                  else if (topics.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),

                      child: DropdownButtonFormField<int>(
                        value: effectiveId,

                        isExpanded: true,

                        decoration: InputDecoration(
                          labelText: s.isFr
                              ? 'Sujet du programme'
                              : 'Curriculum Topic',

                          labelStyle: const TextStyle(
                            color: Color(0xFF334155),

                            fontWeight: FontWeight.w700,

                            fontSize: 13,
                          ),

                          border: const OutlineInputBorder(),

                          isDense: true,

                          filled: true,

                          fillColor: Colors.white,
                        ),

                        selectedItemBuilder: (_) => topics
                            .map(
                              (t) => Align(
                                alignment: Alignment.centerLeft,

                                child: Text(
                                  t.id < 0
                                      ? '${localizeSubject(t.subjectName, s.isFr)}: ${localizeTopicTitle(t.topicTitle, s.isFr)}'
                                      : '${s.isFr ? "Sem" : "Wk"} ${t.weekNumber} • ${localizeSubject(t.subjectName, s.isFr)}: ${localizeTopicTitle(t.topicTitle, s.isFr)}',

                                  maxLines: 1,

                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),

                                    fontWeight: FontWeight.w700,

                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),

                        items: topics
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,

                                child: Text(
                                  t.id < 0
                                      ? '${localizeSubject(t.subjectName, s.isFr)}: ${localizeTopicTitle(t.topicTitle, s.isFr)}'
                                      : '${s.isFr ? "Sem" : "Wk"} ${t.weekNumber} • ${localizeSubject(t.subjectName, s.isFr)}: ${localizeTopicTitle(t.topicTitle, s.isFr)}',

                                  maxLines: 2,

                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),

                                    fontWeight: FontWeight.w600,

                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),

                        onChanged: (val) {
                          if (val == null || val == _selectedProgressionId)
                            return;

                          setState(() {
                            _selectedProgressionId = val;

                            _customTopic = null;

                            _customSubject = null;

                            _resetTopicWorkspace();
                          });

                          if (_mode == AiMode.summary) {
                            _runAiAction(provider, s);
                          }
                        },
                      ),
                    ),

                  SizedBox(
                    width: double.infinity,

                    child: SegmentedButton<AiMode>(
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }

                          return const Color(0xFF1E293B);
                        }),

                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.selected)) {
                            return const Color(0xFF1E293B);
                          }

                          return Colors.white;
                        }),

                        textStyle: WidgetStateProperty.resolveWith((states) {
                          return const TextStyle(
                            fontSize: 12,

                            fontWeight: FontWeight.w700,
                          );
                        }),
                      ),

                      segments: [
                        ButtonSegment(
                          value: AiMode.ask,

                          icon: const Icon(Icons.chat_bubble_outline),

                          label: Text(s.aiModeAsk),
                        ),

                        ButtonSegment(
                          value: AiMode.quiz,

                          icon: const Icon(Icons.quiz_outlined),

                          label: Text(s.aiModeQuiz),
                        ),

                        ButtonSegment(
                          value: AiMode.summary,

                          icon: const Icon(Icons.summarize_outlined),

                          label: Text(s.aiModeSummary),
                        ),
                      ],

                      selected: {_mode},

                      onSelectionChanged: (sel) {
                        final chosen = sel.first;

                        if (_isGeneralChat && chosen != AiMode.ask) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                s.isFr
                                    ? 'Choisissez un sujet de cours pour générer un résumé ou un quiz.'
                                    : 'Pick a curriculum topic to generate a summary or quiz.',
                              ),

                              duration: const Duration(seconds: 2),
                            ),
                          );

                          return;
                        }

                        setState(() => _mode = chosen);
                        if (chosen == AiMode.quiz) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _autoTranslateQuizIfNeeded(context.read<StudyProvider>());
                            }
                          });
                        } else if (chosen == AiMode.summary) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _autoTranslateSummaryIfNeeded(context.read<StudyProvider>());
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView(
              controller: _scrollController,

              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),

              children: [
                if (_mode != AiMode.ask) ...[
                  FilledButton.icon(
                    onPressed: _isCurrentModeLoading
                        ? () {}
                        : () => _runAiAction(provider, s),

                    style: FilledButton.styleFrom(
                      backgroundColor: _isCurrentModeLoading
                          ? const Color(0xFF1E293B)
                          : const Color(0xFF4F46E5),

                      foregroundColor: Colors.white,

                      padding: const EdgeInsets.symmetric(
                        vertical: 14,

                        horizontal: 16,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    icon: _isCurrentModeLoading
                        ? const SizedBox(
                            width: 18,

                            height: 18,

                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,

                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.auto_awesome, color: Colors.white),

                    label: Text(
                      _isCurrentModeLoading
                          ? (s.isFr
                                ? s.isFr
                                      ? 'Génération en cours...'
                                      : 'Generating...'
                                : 'Searching & Thinking...')
                          : _mode == AiMode.quiz
                          ? (s.isFr
                                ? 'Générer un Quiz (QCM + Rédaction)'
                                : 'Generate Mixed Quiz (MCQ + Essay)')
                          : (s.isFr
                                ? 'Générer un Résumé Vérifié'
                                : 'Generate Verified Summary'),

                      style: const TextStyle(
                        fontSize: 15,

                        fontWeight: FontWeight.w700,

                        color: Colors.white,
                      ),
                    ),
                  ),

                  if (_isCurrentModeLoading) ...[
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,

                        vertical: 12,
                      ),

                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: const Color(0xFF3B82F6),

                          width: 1.5,
                        ),
                      ),

                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,

                            height: 20,

                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,

                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF1D4ED8),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              s.isFr
                                  ? s.isFr
                                        ? 'Génération du cours complet et simulation...'
                                        : 'Generating complete lesson notes & simulation...'
                                  : 'Searching & verifying against official curriculum sources...',

                              style: const TextStyle(
                                fontSize: 13.5,

                                fontWeight: FontWeight.w700,

                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                ],

                if (_mode == AiMode.ask) ...[
                  if (_chatMessages.isEmpty && !_loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 56),

                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),

                            decoration: BoxDecoration(
                              color: _aiPurple.withAlpha(24),

                              shape: BoxShape.circle,
                            ),

                            child: const Icon(
                              Icons.auto_awesome,

                              color: _aiPurple,

                              size: 28,
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            s.isFr
                                ? 'Comment puis-je vous aider ?'
                                : 'How can I help you learn today?',

                            textAlign: TextAlign.center,

                            style: const TextStyle(
                              fontSize: 17,

                              fontWeight: FontWeight.w700,

                              color: _deepNavy,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            s.isFr
                                ? 'Posez une question, partagez un exercice ou explorez votre programme.'
                                : 'Ask a question, share an exercise, or explore your curriculum.',

                            textAlign: TextAlign.center,

                            style: const TextStyle(
                              fontSize: 13,

                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),

                  for (final msg in _chatMessages) ...[
                    if (msg.role == 'user')
                      Align(
                        alignment: Alignment.centerRight,

                        child: Container(
                          margin: const EdgeInsets.only(
                            top: 8,

                            bottom: 8,

                            left: 48,
                          ),

                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,

                            vertical: 12,
                          ),

                          decoration: const BoxDecoration(
                            color: Color(0xFFE0E7FF),

                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(18),

                              topRight: Radius.circular(18),

                              bottomLeft: Radius.circular(18),

                              bottomRight: Radius.circular(4),
                            ),
                          ),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,

                            children: [
                              if (msg.images.isNotEmpty) ...[
                                Wrap(
                                  spacing: 8,

                                  runSpacing: 8,

                                  children: [
                                    for (final img in msg.images)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),

                                        child: Image.memory(
                                          img,

                                          height: 160,

                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                  ],
                                ),

                                if (msg.text.isNotEmpty)
                                  const SizedBox(height: 8),
                              ],

                              if (msg.text.isNotEmpty)
                                SelectableText(
                                  cleanMathNotation(msg.text),

                                  style: const TextStyle(
                                    color: Color(0xFF1E105A),

                                    fontSize: 15,

                                    height: 1.35,

                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Align(
                        alignment: Alignment.centerLeft,

                        child: Container(
                          margin: const EdgeInsets.only(
                            top: 4,

                            bottom: 12,

                            right: 12,
                          ),

                          padding: const EdgeInsets.all(16),

                          decoration: BoxDecoration(
                            color: Colors.white,

                            borderRadius: BorderRadius.circular(16),

                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),

                                blurRadius: 8,

                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              TeacherNotesView(
                                content: msg.text,

                                isFr: s.isFr,

                                studentName: provider.user?.fullName,
                              ),

                              if (msg.simulation != null &&
                                  msg.simulation!.steps.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),

                                  child: _buildSimulationPlayer(
                                    msg.simulation!,

                                    s,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],

                  if (_loading)
                    Align(
                      alignment: Alignment.centerLeft,

                      child: Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 12),

                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,

                          vertical: 12,
                        ),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(16),
                        ),

                        child: Row(
                          mainAxisSize: MainAxisSize.min,

                          children: [
                            const SizedBox(
                              width: 16,

                              height: 16,

                              child: CircularProgressIndicator(
                                strokeWidth: 2,

                                color: _aiPurple,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Text(
                              s.isFr
                                  ? 'Kivora réfléchit...'
                                  : 'Kivora is thinking...',

                              style: const TextStyle(
                                fontSize: 13,

                                color: Color(0xFF64748B),

                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_chatMessages.isNotEmpty)
                    _buildProgressStatusBar(provider, s, effectiveId),
                ],

                if (_mode == AiMode.summary &&
                    _summaryOutput == null &&
                    _summaryFollowUps.isEmpty &&
                    !_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),

                    child: Text(
                      s.isFr
                          ? 'Cliquez sur "Générer un Résumé Vérifié" pour obtenir le cours complet avec sources et simulations vidéo.'
                          : 'Tap "Generate Verified Summary" for complete detailed notes, verified reference links, and video simulations.',

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        fontSize: 14,

                        color: Color(0xFF475569),
                      ),
                    ),
                  ),

                if (_mode == AiMode.quiz &&
                    _quiz.isEmpty &&
                    _quizFeedback == null &&
                    _quizFollowUps.isEmpty &&
                    !_loading &&
                    !_grading)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),

                    child: Text(
                      s.isFr
                          ? 'Générez un quiz pour pratiquer (QCM + rédaction ou photo de votre feuille) et recevoir des explications adaptées à votre style.'
                          : 'Generate a quiz to practice MCQs & essay questions (or upload your handwritten paper) and get tailored explanations + simulations.',

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        fontSize: 14,

                        color: Color(0xFF475569),
                      ),
                    ),
                  ),

                if (_mode == AiMode.summary) ...[
                  if (_translating)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),

                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,

                        vertical: 12,
                      ),

                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: const Color(0xFF3B82F6),

                          width: 1.5,
                        ),
                      ),

                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,

                            height: 18,

                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,

                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF1D4ED8),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              s.isFr
                                  ? 'Traduction automatique en français...'
                                  : 'Translating everything to English...',

                              style: const TextStyle(
                                fontSize: 13.5,

                                fontWeight: FontWeight.w700,

                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_summaryOutput != null) ...[
                    Card(
                      color: Colors.white,

                      child: Padding(
                        padding: const EdgeInsets.all(16),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Wrap(
                              spacing: 8,

                              runSpacing: 6,

                              children: [
                                if (_summarySources.isNotEmpty)
                                  Chip(
                                    avatar: const Icon(
                                      Icons.verified_outlined,

                                      size: 16,

                                      color: Color(0xFF047857),
                                    ),

                                    backgroundColor: const Color(0xFFECFDF5),

                                    label: Text(
                                      s.isFr
                                          ? 'Vérifié sur ${_summarySources.length} sources'
                                          : 'Verified across ${_summarySources.length} online sources',

                                      style: const TextStyle(
                                        color: Color(0xFF065F46),

                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            if (s.isFr &&
                                RegExp(
                                      r'\b(the|and|is|are|welcome|lesson|class|today|this|that|with)\b',

                                      caseSensitive: false,
                                    ).allMatches(_summaryOutput!).length >=
                                    4)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),

                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,

                                  vertical: 10,
                                ),

                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),

                                  borderRadius: BorderRadius.circular(12),

                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),

                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.translate,

                                      size: 20,

                                      color: Color(0xFF1D4ED8),
                                    ),

                                    const SizedBox(width: 10),

                                    const Expanded(
                                      child: Text(
                                        'Ce cours est affiché en anglais. Cliquez pour le générer en français vérifié.',

                                        style: TextStyle(
                                          fontSize: 13,

                                          color: Color(0xFF1E3A8A),

                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),

                                    FilledButton.tonalIcon(
                                      onPressed: _loading
                                          ? null
                                          : () => _runAiAction(provider, s),

                                      icon: const Icon(
                                        Icons.auto_awesome,

                                        size: 16,
                                      ),

                                      label: const Text('En français'),
                                    ),
                                  ],
                                ),
                              )
                            else if (!s.isFr &&
                                RegExp(
                                      r'\b(le|la|les|dans|nous|cours|avec|pour|est|sont)\b',

                                      caseSensitive: false,
                                    ).allMatches(_summaryOutput!).length >=
                                    4)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),

                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,

                                  vertical: 10,
                                ),

                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),

                                  borderRadius: BorderRadius.circular(12),

                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),

                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.translate,

                                      size: 20,

                                      color: Color(0xFF1D4ED8),
                                    ),

                                    const SizedBox(width: 10),

                                    const Expanded(
                                      child: Text(
                                        'This lesson is currently in French. Click to generate in verified English.',

                                        style: TextStyle(
                                          fontSize: 13,

                                          color: Color(0xFF1E3A8A),

                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),

                                    FilledButton.tonalIcon(
                                      onPressed: _loading
                                          ? null
                                          : () => _runAiAction(provider, s),

                                      icon: const Icon(
                                        Icons.auto_awesome,

                                        size: 16,
                                      ),

                                      label: const Text('In English'),
                                    ),
                                  ],
                                ),
                              ),

                            TeacherNotesView(
                              content: _summaryOutput!,

                              inlineImages: _summarySources,

                              inlineDiagrams: _summaryDiagrams,

                              isFr: s.isFr,

                              studentName: provider.user?.fullName,
                            ),

                            Padding(
                              padding: const EdgeInsets.only(
                                top: 12,
                                bottom: 8,
                              ),
                              child: _buildSimulationPlayer(
                                _summarySimulation ??
                                    _fallbackSimulation(
                                      _summaryOutput!,
                                      s.isFr,
                                    ),
                                s,
                              ),
                            ),
                            _buildLinksCard(
                              title: s.isFr
                                  ? 'Liens exacts des sources consultées (cliquez pour ouvrir) :'
                                  : 'Exact Reference Sources Used (click to open):',

                              items: _summarySources,

                              icon: Icons.link_rounded,

                              accentColor: _primaryBlue,
                            ),
                          ],
                        ),
                      ),
                    ),

                    _buildProgressStatusBar(provider, s, effectiveId),
                  ],

                  _buildFollowUpsSection(_summaryFollowUps, s),
                ],

                if (_mode == AiMode.quiz) ...[
                  if (_quiz.isNotEmpty) ...[
                    const SizedBox(height: 8),

                    if (_quizPaperImages.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),

                        padding: const EdgeInsets.all(12),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(14),

                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                            width: 1.5,
                          ),

                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E3A8A).withOpacity(0.06),

                              blurRadius: 10,

                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.image_outlined,
                                  color: _primaryBlue,
                                  size: 20,
                                ),

                                const SizedBox(width: 8),

                                Text(
                                  s.isFr
                                      ? 'Photo(s) du sujet / exercice'
                                      : 'Exercise / Question Photo(s)',

                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,

                                    fontSize: 13.5,

                                    color: _deepNavy,
                                  ),
                                ),

                                const Spacer(),

                                TextButton.icon(
                                  onPressed: _grading
                                      ? null
                                      : _pickQuizPaperImages,

                                  icon: const Icon(
                                    Icons.add_photo_alternate,
                                    size: 16,
                                  ),

                                  label: Text(s.isFr ? 'Ajouter' : 'Add'),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            Wrap(
                              spacing: 10,

                              runSpacing: 10,

                              children: List.generate(_quizPaperImages.length, (
                                idx,
                              ) {
                                final img = _quizPaperImages[idx];

                                return Stack(
                                  clipBehavior: Clip.none,

                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),

                                      child: Image.memory(
                                        img.bytes,

                                        width: 140,

                                        height: 140,

                                        fit: BoxFit.cover,
                                      ),
                                    ),

                                    Positioned(
                                      top: -6,

                                      right: -6,

                                      child: InkWell(
                                        onTap: () => setState(
                                          () => _quizPaperImages.removeAt(idx),
                                        ),

                                        child: Container(
                                          padding: const EdgeInsets.all(3),

                                          decoration: const BoxDecoration(
                                            color: Color(0xFF0F172A),

                                            shape: BoxShape.circle,
                                          ),

                                          child: const Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),

                        child: OutlinedButton.icon(
                          onPressed: _grading ? null : _pickQuizPaperImages,

                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,

                            side: const BorderSide(color: Color(0xFFCBD5E1)),

                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                          icon: const Icon(
                            Icons.add_a_photo_outlined,
                            size: 18,
                            color: _primaryBlue,
                          ),

                          label: Text(
                            s.isFr
                                ? 'Joindre une photo du sujet / exercice'
                                : 'Upload exercise photo / worksheet',

                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _deepNavy,
                            ),
                          ),
                        ),
                      ),

                    ...List.generate(_quiz.length, (qIdx) {
                      final q = _quiz[qIdx];

                      final chosen = _selectedAnswers[qIdx];

                      final isWrongMcq =
                          chosen != null && q.isMcq && chosen != q.correctIndex;

                      final typeLabel = q.questionType == 'essay'
                          ? (s.isFr ? 'Rédaction / Essai' : 'Essay')
                          : (q.questionType == 'short_answer'
                                ? (s.isFr ? 'Réponse courte' : 'Short Answer')
                                : 'MCQ');

                      final badgeColor = q.questionType == 'essay'
                          ? _aiPurple
                          : (q.questionType == 'short_answer'
                                ? const Color(0xFF0284C7)
                                : _primaryBlue);

                      return Card(
                        color: Colors.white,

                        margin: const EdgeInsets.only(bottom: 12),

                        child: Padding(
                          padding: const EdgeInsets.all(14),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,

                                      vertical: 3,
                                    ),

                                    decoration: BoxDecoration(
                                      color: badgeColor.withAlpha(24),

                                      borderRadius: BorderRadius.circular(8),
                                    ),

                                    child: Text(
                                      '$typeLabel · ${q.marks} ${q.marks == 1 ? "mk" : "mks"}',

                                      style: TextStyle(
                                        color: badgeColor,

                                        fontWeight: FontWeight.w700,

                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              Text(
                                'Q${qIdx + 1}. ${q.question}',

                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 8),

                              if (q.isMcq)
                                ...List.generate(q.options.length, (optIdx) {
                                  final isSelected = chosen == optIdx;

                                  final isCorrect = optIdx == q.correctIndex;

                                  Color? tileColor;

                                  if (chosen != null) {
                                    if (isCorrect) {
                                      tileColor = Colors.green.withAlpha(45);
                                    } else if (isSelected) {
                                      tileColor = Colors.red.withAlpha(45);
                                    }
                                  }

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),

                                    decoration: BoxDecoration(
                                      color: tileColor,

                                      borderRadius: BorderRadius.circular(8),

                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.grey.withAlpha(70),
                                      ),
                                    ),

                                    child: ListTile(
                                      dense: true,

                                      title: Text(q.options[optIdx]),

                                      onTap: () => setState(
                                        () => _selectedAnswers[qIdx] = optIdx,
                                      ),
                                    ),
                                  );
                                })
                              else
                                TextField(
                                  controller: _ctrlForQuestion(qIdx),

                                  minLines: q.questionType == 'essay' ? 4 : 2,

                                  maxLines: 8,

                                  decoration: InputDecoration(
                                    hintText: s.isFr
                                        ? 'Écrivez votre réponse ici — ou résolvez sur papier et importez une photo ci-dessous...'
                                        : 'Type your answer here — or solve on paper and upload a photo below...',

                                    filled: true,

                                    fillColor: const Color(0xFFF8FAFC),

                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),

                              if (chosen != null && q.isMcq)
                                Container(
                                  width: double.infinity,

                                  margin: const EdgeInsets.only(top: 8),

                                  padding: const EdgeInsets.all(10),

                                  decoration: BoxDecoration(
                                    color: isWrongMcq
                                        ? const Color(0xFFFEF2F2)
                                        : const Color(0xFFECFDF5),

                                    borderRadius: BorderRadius.circular(8),

                                    border: Border.all(
                                      color: isWrongMcq
                                          ? const Color(0xFFFECACA)
                                          : const Color(0xFFA7F3D0),
                                    ),
                                  ),

                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,

                                    children: [
                                      Text(
                                        isWrongMcq
                                            ? (s.isFr
                                                  ? 'Pourquoi votre choix est incorrect :'
                                                  : 'Why your choice is incorrect:')
                                            : (s.isFr
                                                  ? 'Bonne réponse ! Pourquoi :'
                                                  : 'Correct! Why it is right:'),

                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,

                                          fontSize: 12,

                                          color: isWrongMcq
                                              ? const Color(0xFF991B1B)
                                              : const Color(0xFF065F46),
                                        ),
                                      ),

                                      if (q.explanation.isNotEmpty) ...[
                                        const SizedBox(height: 3),

                                        Text(
                                          q.explanation,

                                          style: const TextStyle(
                                            fontSize: 12.5,

                                            height: 1.35,
                                          ),
                                        ),
                                      ],

                                      if (isWrongMcq) ...[
                                        const SizedBox(height: 6),

                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,

                                              vertical: 4,
                                            ),

                                            minimumSize: Size.zero,

                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),

                                          onPressed: _loading
                                              ? null
                                              : () => _explainWrongMcq(
                                                  provider,

                                                  s,

                                                  qIdx,

                                                  q,

                                                  chosen,
                                                ),

                                          icon: const Icon(
                                            Icons.play_circle_outline_rounded,

                                            size: 16,
                                          ),

                                          label: Text(
                                            s.isFr
                                                ? 'Expliquer avec exemple & simulation vidéo'
                                                : 'Explain why & propose video simulation',

                                            style: const TextStyle(
                                              fontSize: 12,

                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    Card(
                      color: const Color(0xFFF8FAFC),

                      margin: const EdgeInsets.only(bottom: 12),

                      child: Padding(
                        padding: const EdgeInsets.all(14),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              s.isFr
                                  ? 'Répondu sur papier ? Importez votre feuille pour correction IA'
                                  : 'Solved on Paper? Upload Your Work for AI Correction',

                              style: const TextStyle(
                                fontWeight: FontWeight.w800,

                                color: _deepNavy,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Text(
                              s.isFr
                                  ? 'L’IA repère la moindre erreur, corrige avec vos loisirs et lance une simulation.'
                                  : 'Kivora inspects every line, catches slight errors, corrects using your hobbies, and builds a visual simulation.',

                              style: const TextStyle(
                                fontSize: 12.5,

                                color: Color(0xFF475569),
                              ),
                            ),

                            const SizedBox(height: 10),

                            OutlinedButton.icon(
                              onPressed: _grading ? null : _pickQuizPaperImages,

                              icon: const Icon(Icons.add_a_photo_outlined),

                              label: Text(
                                s.isFr
                                    ? 'Joindre Photo(s) de ma feuille'
                                    : 'Upload Handwritten Paper Photo(s)',
                              ),
                            ),

                            if (_quizPaperImages.isNotEmpty) ...[
                              const SizedBox(height: 10),

                              Wrap(
                                spacing: 8,

                                runSpacing: 8,

                                children: List.generate(
                                  _quizPaperImages.length,

                                  (idx) {
                                    final img = _quizPaperImages[idx];

                                    return Stack(
                                      clipBehavior: Clip.none,

                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),

                                          child: Image.memory(
                                            img.bytes,

                                            width: 74,

                                            height: 74,

                                            fit: BoxFit.cover,
                                          ),
                                        ),

                                        Positioned(
                                          top: -6,

                                          right: -6,

                                          child: InkWell(
                                            onTap: () => setState(
                                              () => _quizPaperImages.removeAt(
                                                idx,
                                              ),
                                            ),

                                            child: Container(
                                              padding: const EdgeInsets.all(3),

                                              decoration: const BoxDecoration(
                                                color: Color(0xFF0F172A),

                                                shape: BoxShape.circle,
                                              ),

                                              child: const Icon(
                                                Icons.close,

                                                size: 13,

                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),

                            TextField(
                              controller: _quizNoteCtrl,

                              decoration: InputDecoration(
                                hintText: s.isFr
                                    ? 'Note optionnelle (ex: J’ai hésité sur la question 4)...'
                                    : 'Optional note (e.g. Please check my Q4 working)...',

                                isDense: true,

                                filled: true,

                                fillColor: Colors.white,

                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,

                              child: FilledButton.icon(
                                onPressed: _grading
                                    ? null
                                    : () => _gradeQuizSubmission(provider, s),

                                icon: _grading
                                    ? const SizedBox(
                                        width: 18,

                                        height: 18,

                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,

                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.fact_check_outlined),

                                label: Text(
                                  _grading
                                      ? (s.isFr
                                            ? 'Inspection et correction IA...'
                                            : 'Checking Work & Building Simulation...')
                                      : (s.isFr
                                            ? 'Corriger mes réponses & lancer la simulation'
                                            : 'Submit Answers / Paper for AI Correction'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (_quizFeedback != null)
                    Card(
                      color: Colors.white,

                      margin: const EdgeInsets.only(bottom: 12),

                      child: Padding(
                        padding: const EdgeInsets.all(16),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            if (_scoreSummary != null &&
                                _scoreSummary!.isNotEmpty)
                              Container(
                                width: double.infinity,

                                margin: const EdgeInsets.only(bottom: 12),

                                padding: const EdgeInsets.all(12),

                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),

                                  borderRadius: BorderRadius.circular(12),

                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),

                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.grading_rounded,

                                      color: _primaryBlue,
                                    ),

                                    const SizedBox(width: 10),

                                    Expanded(
                                      child: Text(
                                        _scoreSummary!,

                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,

                                          color: _deepNavy,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            TeacherNotesView(
                              content: _quizFeedback!,

                              isFr: s.isFr,

                              studentName: provider.user?.fullName,
                            ),

                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,

                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _aiPurple,

                                  side: const BorderSide(color: _aiPurple),
                                ),

                                onPressed: _loading
                                    ? null
                                    : () => _explainQuizMistakesSimpler(
                                        provider,

                                        s,
                                      ),

                                icon: const Icon(
                                  Icons.psychology_alt_rounded,

                                  size: 18,
                                ),

                                label: Text(
                                  s.isFr
                                      ? 'Ré-expliquer mes erreurs plus simplement (Simulation + Loisirs)'
                                      : 'Explain What I Missed Even Simpler (Visual + Hobby Example)',

                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,

                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_quiz.isNotEmpty || _quizFeedback != null)
                    _buildProgressStatusBar(provider, s, effectiveId),

                  _buildFollowUpsSection(_quizFollowUps, s),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                _buildAttachmentsPreview(),

                _buildComposerPill(provider, s),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
