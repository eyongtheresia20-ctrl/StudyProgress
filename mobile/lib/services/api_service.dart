import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/study_models.dart';

class ApiService {

  String baseUrl;

  final String? token;

  final String languageCode;

  ApiService(this.baseUrl, {this.token, this.languageCode = 'en'});

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
      addHost('https://solaris-headlines-targeted-dive.trycloudflare.com');
      addHost('http://192.168.1.164:8000');
      addHost('http://10.0.2.2:8000');
    }

    return list;

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
            .timeout(timeout);
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
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastErr;
    final hosts = _candidateHosts;
    for (final host in hosts) {
      try {
        final uri = Uri.parse('$host$path');
        final res = await http.get(uri, headers: _headers).timeout(timeout);
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

    throw lastErr ?? Exception('Server unreachable');

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

    throw lastErr ?? Exception('Server unreachable');

  }

  Future<AppUser> getMe() async {
    final res = await _getWithFallback('/auth/me', timeout: const Duration(seconds: 10));
    return AppUser.fromJson(_decodeMap(res));
  }

  Future<AppUser> updateProfile({

    String? fullName,

    String? email,

    String? currentPassword,

    String? newPassword,

  }) async {

    final body = <String, dynamic>{};

    if (fullName != null) body['full_name'] = fullName;

    if (email != null) body['email'] = email;

    if (currentPassword != null && currentPassword.isNotEmpty) {

      body['current_password'] = currentPassword;

    }

    if (newPassword != null && newPassword.isNotEmpty) {

      body['new_password'] = newPassword;

    }

    final res = await http

        .patch(

          _uri('/auth/profile'),

          headers: _headers,

          body: jsonEncode(body),

        )

        .timeout(const Duration(seconds: 10));

    return AppUser.fromJson(_decodeMap(res));

  }

  Future<List<Subsystem>> getSubsystems() async {
    final res = await _getWithFallback('/curriculum/subsystems', timeout: const Duration(seconds: 10));
    final list = _decodeList(res);
    return list
        .map((e) => Subsystem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> getClassSubjects(int classId) async {

    try {

      final res = await http

          .get(_uri('/curriculum/classes/$classId/subjects'), headers: _headers)

          .timeout(const Duration(seconds: 8));

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

  }) async {

    final res = await http

        .put(

          _uri('/curriculum/student/questionnaire'),

          headers: _headers,

          body: jsonEncode({

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

          }),

        )

        .timeout(const Duration(seconds: 10));

    return StudentProfile.fromJson(_decodeMap(res));

  }

  Future<StudentHomeData> getStudentHome() async {

    final res = await http

        .get(_uri('/curriculum/student/home'), headers: _headers)

        .timeout(const Duration(seconds: 10));

    return StudentHomeData.fromJson(_decodeMap(res));

  }

  Future<StudentHomeData> updateTopicProgress({

    required int progressionId,

    required String status,

    required String understandingLevel,

    int? quizScore,

    String? weaknessNotes,

  }) async {

    final res = await http

        .post(

          _uri('/curriculum/student/progress'),

          headers: _headers,

          body: jsonEncode({

            'progression_id': progressionId,

            'status': status,

            'understanding_level': understandingLevel,

            'quiz_score': quizScore,

            'weakness_notes': weaknessNotes,

          }),

        )

        .timeout(const Duration(seconds: 10));

    return StudentHomeData.fromJson(_decodeMap(res));

  }

  Future<AdminDashboardData> getAdminDashboard() async {

    final res = await http

        .get(_uri('/curriculum/admin/dashboard'), headers: _headers)

        .timeout(const Duration(seconds: 10));

    return AdminDashboardData.fromJson(_decodeMap(res));

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

  }) async {

    final res = await http

        .post(

          _uri('/curriculum/admin/progressions'),

          headers: _headers,

          body: jsonEncode({

            'subsystem_id': subsystemId,

            'class_id': classId,

            'subject_name': subjectName,

            'topic_title': topicTitle,

            'subtopics': subtopics,

            'week_number': weekNumber,

            'start_date': startDate,

            'end_date': endDate,

            'study_days': studyDays,

          }),

        )

        .timeout(const Duration(seconds: 10));

    return OfficialProgression.fromJson(_decodeMap(res));

  }

  Future<Map<String, dynamic>> uploadCurriculumFiles({

    required List<({String name, List<int> bytes})> files,

  }) async {

    return _uploadMultipartFiles('/curriculum/admin/upload-curriculum', files);

  }

  Future<Map<String, dynamic>> uploadProgramsFiles({

    required List<({String name, List<int> bytes})> files,

  }) async {

    return _uploadMultipartFiles('/curriculum/admin/programs/upload', files);

  }

  Future<Map<String, dynamic>> uploadProgressionsFiles({

    required List<({String name, List<int> bytes})> files,

  }) async {

    return _uploadMultipartFiles(

        '/curriculum/admin/progressions/upload', files);

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

  Future<String> getProgramTemplate() async {

    final res = await http

        .get(_uri('/curriculum/admin/programs/template'), headers: _headers)

        .timeout(const Duration(seconds: 10));

    if (res.statusCode >= 400) {

      throw Exception(_extractError(res));

    }

    return res.body;

  }

  Future<String> getProgressionTemplate() async {

    final res = await http

        .get(_uri('/curriculum/admin/progressions/template'), headers: _headers)

        .timeout(const Duration(seconds: 10));

    if (res.statusCode >= 400) {

      throw Exception(_extractError(res));

    }

    return res.body;

  }

  Future<List<OfficialProgression>> exploreTopics({

    String? subject,

    String? query,

  }) async {

    final params = <String, String>{};

    if (subject != null && subject.trim().isNotEmpty) {

      params['subject'] = subject.trim();

    }

    if (query != null && query.trim().isNotEmpty) {

      params['q'] = query.trim();

    }

    final uri = _uri('/curriculum/explore/topics')

        .replace(queryParameters: params.isEmpty ? null : params);

    final res = await http

        .get(uri, headers: _headers)

        .timeout(const Duration(seconds: 10));

    final list = _decodeList(res);

    return list

        .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))

        .toList();

  }

  Future<Map<String, dynamic>> getBackgroundDigest() async {

    final res = await http

        .get(_uri('/curriculum/student/background-digest'), headers: _headers)

        .timeout(const Duration(seconds: 10));

    return _decodeMap(res);

  }

  Future<void> deleteOfficialProgression(int progressionId) async {

    final res = await http

        .delete(

          _uri('/curriculum/admin/progressions/$progressionId'),

          headers: _headers,

        )

        .timeout(const Duration(seconds: 10));

    if (res.statusCode >= 400) {

      throw Exception(_extractError(res));

    }

  }

  Future<void> deleteUploadedFolder(String folderName) async {

    final encoded = Uri.encodeComponent(folderName);

    final res = await http

        .delete(

          _uri('/curriculum/admin/uploaded-folders/$encoded'),

          headers: _headers,

        )

        .timeout(const Duration(seconds: 15));

    if (res.statusCode >= 400) {

      throw Exception(_extractError(res));

    }

  }

  Future<List<Map<String, dynamic>>> getAdminUsers() async {

    final res = await http

        .get(_uri('/curriculum/admin/users'), headers: _headers)

        .timeout(const Duration(seconds: 35));

    final list = _decodeList(res);

    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  }

  Future<Map<String, dynamic>> createAdminUser({

    required String fullName,

    required String email,

    required String password,

    String role = 'student',

    int? subsystemId,

    int? classId,

  }) async {

    final res = await http

        .post(

          _uri('/curriculum/admin/users'),

          headers: _headers,

          body: jsonEncode({

            'full_name': fullName,

            'email': email,

            'password': password,

            'role': role,

            'subsystem_id': subsystemId,

            'class_id': classId,

          }),

        )

        .timeout(const Duration(seconds: 15));

    return _decodeMap(res);

  }

  Future<Map<String, dynamic>> updateUserStatus(

    int userId,

    bool isActive,

  ) async {

    final res = await http

        .put(

          _uri('/curriculum/admin/users/$userId/status'),

          headers: _headers,

          body: jsonEncode({'is_active': isActive}),

        )

        .timeout(const Duration(seconds: 35));

    return _decodeMap(res);

  }

  Future<void> deleteAdminUser(int userId) async {

    final res = await http

        .delete(

          _uri('/curriculum/admin/users/$userId'),

          headers: _headers,

        )

        .timeout(const Duration(seconds: 35));

    if (res.statusCode >= 400) {

      throw Exception(_extractError(res));

    }

  }

  Future<AiResponse> askTutor({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    required String question,
  }) async {
    final res = await _postWithFallback(
      '/ai/ask',
      body: {
        'progression_id': progressionId,
        'subject_name': subjectName,
        'topic_title': topicTitle,
        'question': question,
      },
      timeout: const Duration(seconds: 45),
    );
    return AiResponse.fromJson(_decodeMap(res));
  }

  Future<AiResponse> askTutorMultimodal({

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    String question = '',

    required List<({String name, List<int> bytes})> mediaFiles,

  }) async {

    final req = http.MultipartRequest('POST', _uri('/ai/ask-multimodal'));

    req.headers['X-App-Language'] = languageCode;

    if (token != null && token!.isNotEmpty) {

      req.headers['Authorization'] = 'Bearer $token';

    }

    req.fields['question'] = question;

    if (progressionId != null) {

      req.fields['progression_id'] = progressionId.toString();

    }

    if (subjectName != null && subjectName.isNotEmpty) {

      req.fields['subject_name'] = subjectName;

    }

    if (topicTitle != null && topicTitle.isNotEmpty) {

      req.fields['topic_title'] = topicTitle;

    }

    for (final media in mediaFiles) {

      req.files.add(

        http.MultipartFile.fromBytes('files', media.bytes, filename: media.name),

      );

    }

    final streamed = await req.send().timeout(const Duration(seconds: 75));

    final res = await http.Response.fromStream(streamed);

    return AiResponse.fromJson(_decodeMap(res));

  }

  Future<List<AiHistoryItem>> getAiHistory({int limit = 60}) async {

    final uri = _uri('/ai/history').replace(queryParameters: {'limit': '$limit'});

    final res = await http

        .get(uri, headers: _headers)

        .timeout(const Duration(seconds: 10));

    final list = _decodeList(res);

    return list

        .map((e) => AiHistoryItem.fromJson(e as Map<String, dynamic>))

        .toList();

  }

  Future<bool> deleteAiHistoryItem(int id) async {

    try {

      final res = await http

          .delete(_uri('/ai/history/$id'), headers: _headers)

          .timeout(const Duration(seconds: 10));

      return res.statusCode == 200;

    } catch (_) {

      return false;

    }

  }

  Future<bool> clearAiHistory() async {

    try {

      final res = await http

          .delete(_uri('/ai/history'), headers: _headers)

          .timeout(const Duration(seconds: 10));

      return res.statusCode == 200;

    } catch (_) {

      return false;

    }

  }

  Future<({String text, String modelUsed})> transcribeAudio({

    required String filename,

    required List<int> bytes,

    String language = 'en',

  }) async {

    final req = http.MultipartRequest('POST', _uri('/ai/transcribe'));

    if (token != null && token!.isNotEmpty) {

      req.headers['Authorization'] = 'Bearer $token';

    }

    req.fields['language'] = language;

    req.files.add(

      http.MultipartFile.fromBytes('file', bytes, filename: filename),

    );

    final streamed = await req.send().timeout(const Duration(seconds: 60));

    final res = await http.Response.fromStream(streamed);

    final map = _decodeMap(res);

    return (

      text: (map['text'] as String? ?? '').trim(),

      modelUsed: map['model_used'] as String? ?? '',

    );

  }

  Future<AiResponse> summarizeTopic({

    int? progressionId,

    String? subjectName,

    String? topicTitle,

  }) async {

    Object? lastErr;

    final hosts = _candidateHosts;

    for (final host in hosts) {

      try {

        final uri = Uri.parse('$host/ai/summary');

        final res = await http

            .post(

              uri,

              headers: _headers,

              body: jsonEncode({

                'progression_id': progressionId,

                'subject_name': subjectName,

                'topic_title': topicTitle,

              }),

            )

            .timeout(const Duration(seconds: 30));

        baseUrl = host;

        return AiResponse.fromJson(_decodeMap(res));

      } catch (e) {

        lastErr = e;

      }

    }

    throw lastErr ?? Exception('Server unreachable');

  }

  Future<AiResponse> generateQuiz({
    int? progressionId,
    String? subjectName,
    String? topicTitle,
    int numQuestions = 5,
  }) async {
    final res = await _postWithFallback(
      '/ai/quiz',
      body: {
        'progression_id': progressionId,
        'subject_name': subjectName,
        'topic_title': topicTitle,
        'num_questions': numQuestions,
      },
      timeout: const Duration(seconds: 45),
    );
    return AiResponse.fromJson(_decodeMap(res));
  }

  Future<AiResponse> gradeQuizSubmission({

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    required List<QuizQuestion> quiz,

    required Map<String, dynamic> typedAnswers,

    String note = '',

    List<({String name, List<int> bytes})> paperImages = const [],

  }) async {

    final req = http.MultipartRequest('POST', _uri('/ai/quiz/grade'));

    req.headers['X-App-Language'] = languageCode;

    if (token != null && token!.isNotEmpty) {

      req.headers['Authorization'] = 'Bearer $token';

    }

    if (progressionId != null) {

      req.fields['progression_id'] = progressionId.toString();

    }

    if (subjectName != null && subjectName.isNotEmpty) {

      req.fields['subject_name'] = subjectName;

    }

    if (topicTitle != null && topicTitle.isNotEmpty) {

      req.fields['topic_title'] = topicTitle;

    }

    req.fields['quiz_json'] =

        jsonEncode(quiz.map((q) => q.toJson()).toList());

    req.fields['answers_json'] = jsonEncode(typedAnswers);

    req.fields['note'] = note;

    for (final img in paperImages) {

      req.files.add(

        http.MultipartFile.fromBytes('files', img.bytes, filename: img.name),

      );

    }

    final streamed = await req.send().timeout(const Duration(seconds: 90));

    final res = await http.Response.fromStream(streamed);

    return AiResponse.fromJson(_decodeMap(res));

  }

  Future<String> translateText({

    required String text,

    required String targetLanguage,

  }) async {

    if (text.trim().isEmpty) return text;

    try {

      final res = await http

          .post(

            _uri('/ai/translate'),

            headers: _headers,

            body: jsonEncode({

              'text': text,

              'target_language': targetLanguage,

            }),

          )

          .timeout(const Duration(seconds: 35));

      final data = _decodeMap(res);

      return data['translated_text']?.toString() ?? text;

    } catch (_) {

      return text;

    }

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

}

