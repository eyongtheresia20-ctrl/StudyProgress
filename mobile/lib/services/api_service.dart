import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/study_models.dart';
import 'supabase_cloud_service.dart';
import 'cloud_extras.dart';
class ApiService {
  static const bool cloudOnly = true;
  String baseUrl;
  final String? token;
  final String languageCode;
  AppUser? currentUser;
  final SupabaseCloudService _cloud = SupabaseCloudService();
  final CloudExtras _extras = CloudExtras();
  int get _adminId => currentUser?.id ?? 1;
  ApiService(this.baseUrl, {this.token, this.languageCode = 'en', this.currentUser});
  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$cleanBase$path');
  }
  Map<String, String> get _headers => {
        'Bypass-Tunnel-Reminder': 'true',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-App-Language': languageCode,
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };
  Future<Map<String, dynamic>> checkHealth() async {
    final res = await http
        .get(_uri('/health'), headers: _headers)
        .timeout(const Duration(seconds: 6));
    return _decodeMap(res);
  }
  List<String> get _candidateHosts {
    final list = <String>[];
    if (cloudOnly) return list;
    void addHost(String h) {
      final clean = h.replaceAll(RegExp(r'/+$'), '');
      if (clean.isNotEmpty && !list.contains(clean)) list.add(clean);
    }
    if (kIsWeb) {
      addHost('http://127.0.0.1:8000');
      addHost('http://localhost:8000');
      addHost(baseUrl);
    } else {
      if (baseUrl.isNotEmpty) addHost(baseUrl);
      addHost('http://127.0.0.1:8000');
      addHost('https://maintaining-ruled-integration-drinking.trycloudflare.com');
      addHost('http://192.168.10.233:8000');
      addHost('http://192.168.1.164:8000');
      addHost('http://10.0.2.2:8000');
    }
    return list;
  }
  Duration _effectiveTimeout(String host, Duration requestedTimeout) {
    if (host == baseUrl) return requestedTimeout;
    const maxProbe = Duration(seconds: 12);
    return requestedTimeout < maxProbe ? requestedTimeout : maxProbe;
  }
  Future<http.Response> _postWithFallback(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        final uri = Uri.parse('$host$path');
        final res = await http
            .post(
              uri,
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(_effectiveTimeout(host, timeout));
        if (res.statusCode >= 500) {
          throw Exception("Host ${host} returned HTTP ${res.statusCode}");
        }
        baseUrl = host;
        return res;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Server unreachable');
  }
  Future<http.Response> _getWithFallback(
    String path, {
    Map<String, String>? queryParams,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        var uri = Uri.parse('$host$path');
        if (queryParams != null && queryParams.isNotEmpty) {
          uri = uri.replace(queryParameters: queryParams);
        }
        final res = await http.get(uri, headers: _headers).timeout(_effectiveTimeout(host, timeout));
        if (res.statusCode >= 500) {
          throw Exception("Host ${host} returned HTTP ${res.statusCode}");
        }
        baseUrl = host;
        return res;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Server unreachable');
  }
  Future<http.Response> _putWithFallback(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        final uri = Uri.parse('$host$path');
        final res = await http
            .put(
              uri,
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(_effectiveTimeout(host, timeout));
        if (res.statusCode >= 500) {
          throw Exception("Host ${host} returned HTTP ${res.statusCode}");
        }
        baseUrl = host;
        return res;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Server unreachable');
  }
  Future<http.Response> _patchWithFallback(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        final uri = Uri.parse('$host$path');
        final res = await http
            .patch(
              uri,
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(_effectiveTimeout(host, timeout));
        if (res.statusCode >= 500) {
          throw Exception("Host ${host} returned HTTP ${res.statusCode}");
        }
        baseUrl = host;
        return res;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Server unreachable');
  }
  Future<http.Response> _deleteWithFallback(
    String path, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        final uri = Uri.parse('$host$path');
        final res = await http.delete(uri, headers: _headers).timeout(_effectiveTimeout(host, timeout));
        if (res.statusCode >= 500) {
          throw Exception("Host ${host} returned HTTP ${res.statusCode}");
        }
        baseUrl = host;
        return res;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Server unreachable');
  }
  Future<(String, AppUser)> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    Object? lastErr;
    for (final host in _candidateHosts) {
      try {
        final uri = Uri.parse('$host/auth/register');
        final res = await http
            .post(
              uri,
              headers: _headers,
              body: jsonEncode({
                'full_name': fullName,
                'email': email,
                'password': password,
                'role': role,
              }),
            )
            .timeout(const Duration(seconds: 6));
        baseUrl = host;
        final map = _decodeMap(res);
        return (
          map['access_token'] as String,
          AppUser.fromJson(map['user'] as Map<String, dynamic>),
        );
      } catch (e) {
        lastErr = e;
        final msg = e.toString();
        if (msg.contains('already registered') ||
            msg.contains('Invalid') ||
            msg.contains('detail')) {
          baseUrl = host;
          rethrow;
        }
      }
    }
    // Seamless fallback to Supabase 24/7 Cloud
    try {
      final res = await _cloud.register(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
      );
      currentUser = res.$2;
      return res;
    } catch (cloudErr) {
      throw lastErr ?? cloudErr;
    }
  }
  Future<(String, AppUser)> login({
    required String email,
    required String password,
  }) async {
    Object? lastErr;
    for (final host in _candidateHosts) {
      try {
        final uri = Uri.parse('$host/auth/login');
        final res = await http
            .post(
              uri,
              headers: _headers,
              body: jsonEncode({
                'email': email,
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 6));
        baseUrl = host;
        final map = _decodeMap(res);
        return (
          map['access_token'] as String,
          AppUser.fromJson(map['user'] as Map<String, dynamic>),
        );
      } catch (e) {
        lastErr = e;
        final msg = e.toString();
        if (msg.contains('Invalid') ||
            msg.contains('credentials') ||
            msg.contains('Incorrect') ||
            msg.contains('not found')) {
          baseUrl = host;
          rethrow;
        }
      }
    }
    // Seamless fallback to Supabase 24/7 Cloud
    try {
      final res = await _cloud.login(
        email: email,
        password: password,
      );
      currentUser = res.$2;
      return res;
    } catch (cloudErr) {
      throw lastErr ?? cloudErr;
    }
  }
  Future<AppUser> getMe() async {
    try {
      final u = await _extras.getMe(current: currentUser, token: token);
      currentUser = u;
      return u;
    } catch (e) {
      final s = e.toString();
      final offline = s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('Timeout') ||
          s.contains('Failed host lookup');
      if (offline && currentUser != null) return currentUser!;
      rethrow;
    }
  }
  Future<AppUser> updateProfile({
    String? fullName,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    final u = currentUser;
    if (u == null) throw Exception('Session expirée, reconnectez-vous.');
    final updated = await _extras.updateProfile(
      user: u,
      fullName: fullName,
      email: email,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    currentUser = updated;
    return updated;
  }
  Future<List<Subsystem>> getSubsystems() async {
    if (cloudOnly) return _cloud.getSubsystems();
    final res = await _getWithFallback('/curriculum/subsystems', timeout: const Duration(seconds: 10));
    final list = _decodeList(res);
    return list
        .map((e) => Subsystem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  Future<List<String>> getClassSubjects(int classId) async {
    if (cloudOnly) return _cloud.getClassSubjects(classId);
    try {
      final res = await _getWithFallback(
        '/curriculum/classes/$classId/subjects',
        timeout: const Duration(seconds: 6),
      );
      final list = _decodeList(res);
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }
  Future<StudentProfile> saveQuestionnaire({
    String? fullName,
    required int subsystemId,
    required int classId,
    int? age,
    String? favouriteSubject,
    required List<String> difficultSubjects,
    String? difficultyReason,
    required List<String> hobbies,
    required String activityStyle,
    required String learningStyle,
    required String fallbackPreference,
    required String exercisePreference,
    required String preferredStudyPeriod,
    String? academicGoal,
    required int dailyGoalMinutes,
    required int reminderHour,
    required int reminderMinute,
    List<String>? offeredSubjects,
  }) async {
    if (cloudOnly) {
      final uid = currentUser?.id ?? int.tryParse(token ?? '') ?? 2;
      return _cloud.saveQuestionnaire(
        userId: uid,
        fullName: fullName,
        subsystemId: subsystemId,
        classId: classId,
        age: age ?? 16,
        favouriteSubject: favouriteSubject ?? '',
        difficultSubjects: difficultSubjects,
        difficultyReason: difficultyReason,
        hobbies: hobbies,
        activityStyle: activityStyle,
        learningStyle: learningStyle,
        fallbackPreference: fallbackPreference,
        exercisePreference: exercisePreference,
        preferredStudyPeriod: preferredStudyPeriod,
        academicGoal: academicGoal,
        dailyGoalMinutes: dailyGoalMinutes,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        offeredSubjects: offeredSubjects,
      );
    }
    final res = await _putWithFallback(
      '/curriculum/student/questionnaire',
      body: {
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
        'subsystem_id': subsystemId,
        'class_id': classId,
        'age': age,
        'favourite_subject': favouriteSubject,
        'difficult_subjects': difficultSubjects,
        'difficulty_reason': difficultyReason,
        'hobbies': hobbies,
        'activity_style': activityStyle,
        'learning_style': learningStyle,
        'fallback_preference': fallbackPreference,
        'exercise_preference': exercisePreference,
        'preferred_study_period': preferredStudyPeriod,
        'academic_goal': academicGoal,
        'daily_goal_minutes': dailyGoalMinutes,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        if (offeredSubjects != null) 'offered_subjects': offeredSubjects,
      },
      timeout: const Duration(seconds: 12),
    );
    return StudentProfile.fromJson(_decodeMap(res));
  }
  Future<StudentHomeData> getStudentHome({AppUser? forUser}) async {
    final u = forUser ?? currentUser;
    if (u == null) throw Exception('Session expirée, reconnectez-vous.');
    return _cloud.getStudentHome(u);
  }
  Future<StudentHomeData> updateTopicProgress({
    required int progressionId,
    required String status,
    required String understandingLevel,
    int? quizScore,
    String? weaknessNotes,
    AppUser? forUser,
  }) async {
    final u = forUser ?? currentUser;
    if (u == null) throw Exception('Session expirée, reconnectez-vous.');
    return _cloud.updateTopicProgress(
      user: u,
      progressionId: progressionId,
      status: status,
      understandingLevel: understandingLevel,
      quizScore: quizScore,
      weaknessNotes: weaknessNotes,
    );
  }
  Future<AdminDashboardData> getAdminDashboard() async {
    final admin = currentUser ??
        AppUser(
            id: 1,
            fullName: 'Kivora Admin',
            email: 'admin@kivora.cm',
            role: 'admin',
            questionnaireCompleted: true);
    return _extras.getAdminDashboard(admin);
  }
  Future<OfficialProgression> createOfficialProgression({
    required int subsystemId,
    required int classId,
    required String subjectName,
    required String topicTitle,
    String? subtopics,
    required int weekNumber,
    required String startDate,
    required String endDate,
    String? studyDays,
  }) {
    return _extras.createOfficialProgression(
      adminId: _adminId,
      subsystemId: subsystemId,
      classId: classId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      subtopics: subtopics,
      weekNumber: weekNumber,
      startDate: startDate,
      endDate: endDate,
      studyDays: studyDays,
    );
  }
  Future<Map<String, dynamic>> uploadCurriculumFiles({
    required List<({String name, List<int> bytes})> files,
  }) {
    return _extras.importFiles(files: files, mode: 'curriculum', adminId: _adminId);
  }
  Future<Map<String, dynamic>> uploadProgramsFiles({
    required List<({String name, List<int> bytes})> files,
  }) {
    return _extras.importFiles(files: files, mode: 'programs', adminId: _adminId);
  }
  Future<Map<String, dynamic>> uploadProgressionsFiles({
    required List<({String name, List<int> bytes})> files,
  }) {
    return _extras.importFiles(files: files, mode: 'progressions', adminId: _adminId);
  }
  Future<Map<String, dynamic>> _uploadMultipartFiles(
    String path,
    List<({String name, List<int> bytes})> files,
  ) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (token != null && token!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    for (final f in files) {
      req.files.add(
        http.MultipartFile.fromBytes('files', f.bytes, filename: f.name),
      );
    }
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    return _decodeMap(res);
  }
  Future<String> getProgramTemplate() async => _extras.programTemplate();
  Future<String> getProgressionTemplate() async => _extras.progressionTemplate();
  Future<List<OfficialProgression>> exploreTopics({
    int? subsystemId,
    int? classId,
    String? subjectName,
    String? query,
    int limit = 50,
  }) async {
    if (cloudOnly) {
      return _cloud.exploreTopics(
        subsystemId: subsystemId,
        classId: classId,
        subjectName: subjectName,
        query: query,
        limit: limit,
      );
    }
    final params = <String, String>{'limit': '$limit'};
    if (subsystemId != null) params['subsystem_id'] = '$subsystemId';
    if (classId != null) params['class_id'] = '$classId';
    if (subjectName != null && subjectName.isNotEmpty) {
      params['subject_name'] = subjectName;
    }
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final res = await _getWithFallback('/curriculum/explore/topics', queryParams: params);
    final list = _decodeList(res);
    return list
        .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  Future<Map<String, dynamic>> getBackgroundDigest() async {
    final u = currentUser;
    if (u == null) throw Exception('Session expirée, reconnectez-vous.');
    return _extras.backgroundDigestForUserId(u.id);
  }
  Future<void> deleteOfficialProgression(int progressionId) =>
      _extras.deleteOfficialProgression(progressionId);
  Future<void> deleteUploadedFolder(String folderName) =>
      _extras.deleteUploadedFolder(folderName);
  Future<List<Map<String, dynamic>>> getAdminUsers() => _extras.getAdminUsers();
  Future<Map<String, dynamic>> createAdminUser({
    required String fullName,
    required String email,
    required String password,
    String role = 'student',
    int? subsystemId,
    int? classId,
  }) {
    return _extras.createAdminUser(
      fullName: fullName,
      email: email,
      password: password,
      role: role,
      subsystemId: subsystemId,
      classId: classId,
    );
  }
  Future<Map<String, dynamic>> updateUserStatus(int userId, bool isActive) =>
      _extras.updateUserStatus(userId, isActive);
  Future<void> deleteAdminUser(int userId) => _extras.deleteAdminUser(userId);
  Future<AiResponse> askTutor({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    required String question,
    List<Map<String, String>>? conversationHistory,
  }) {
    return _extras.askTutor(
      user: currentUser,
      question: question,
      progressionId: progressionId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      languageCode: languageCode,
      conversationHistory: conversationHistory,
    );
  }
  Future<AiResponse> askTutorMultimodal({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    String question = '',
    required List<({String name, List<int> bytes})> mediaFiles,
    List<Map<String, String>>? conversationHistory,
  }) {
    return _extras.askTutorMultimodal(
      user: currentUser,
      mediaFiles: mediaFiles,
      progressionId: progressionId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      question: question,
      languageCode: languageCode,
      conversationHistory: conversationHistory,
    );
  }
  Future<List<AiHistoryItem>> getAiHistory({int limit = 60}) async {
    final u = currentUser;
    if (u == null) return [];
    return _extras.getAiHistory(u, limit: limit);
  }
  Future<bool> deleteAiHistoryItem(int id) async {
    final u = currentUser;
    if (u == null) return false;
    try {
      return await _extras.deleteAiHistoryItem(u, id);
    } catch (_) {
      return false;
    }
  }
  Future<bool> clearAiHistory() async {
    final u = currentUser;
    if (u == null) return false;
    try {
      return await _extras.clearAiHistory(u);
    } catch (_) {
      return false;
    }
  }
  Future<({String text, String modelUsed})> transcribeAudio({
    required String filename,
    required List<int> bytes,
    String language = 'en',
  }) {
    return _extras.transcribeAudio(filename: filename, bytes: bytes, language: language);
  }
  Future<AiResponse> summarizeTopic({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
  }) {
    return _extras.summarizeTopic(
      user: currentUser,
      progressionId: progressionId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      languageCode: languageCode,
    );
  }
  Future<AiResponse> generateQuiz({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    int numQuestions = 5,
  }) {
    return _extras.generateQuiz(
      user: currentUser,
      progressionId: progressionId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      numQuestions: numQuestions,
      languageCode: languageCode,
    );
  }
  Future<AiResponse> gradeQuizSubmission({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    required List<QuizQuestion> quiz,
    required Map<String, dynamic> typedAnswers,
    String note = '',
    List<({String name, List<int> bytes})> paperImages = const [],
  }) {
    return _extras.gradeQuizSubmission(
      user: currentUser,
      quiz: quiz,
      typedAnswers: typedAnswers,
      progressionId: progressionId,
      subjectName: subjectName,
      topicTitle: topicTitle,
      note: note,
      paperImages: paperImages,
      languageCode: languageCode,
    );
  }
  Future<String> translateText({
    required String text,
    required String targetLanguage,
  }) async {
    try {
      return await _extras.translateText(text: text, targetLanguage: targetLanguage);
    } catch (_) {
      return text;
    }
  }
  Future<List<QuizQuestion>> translateQuiz({
    required List<QuizQuestion> quiz,
    required String targetLanguage,
  }) async {
    try {
      return await _extras.translateQuiz(quiz: quiz, targetLanguage: targetLanguage);
    } catch (_) {
      return quiz;
    }
  }
  SimulationData buildSimulation(String topic, String subject, bool fr) {
    return _extras.buildSimulation(topic, subject, fr);
  }
  Map<String, dynamic> _decodeMap(http.Response res) {
    if (res.statusCode >= 400) {
      throw Exception(_extractError(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
  List<dynamic> _decodeList(http.Response res) {
    if (res.statusCode >= 400) {
      throw Exception(_extractError(res));
    }
    return jsonDecode(res.body) as List<dynamic>;
  }
  String _extractError(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}: ${res.reasonPhrase ?? 'Request failed'}';
  }

  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final u = currentUser;
    if (u == null) throw Exception('Non connecté');
    return _cloud.changePassword(
      userId: u.id,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }

}
