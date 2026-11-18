import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/study_models.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';

class StudyProvider extends ChangeNotifier {
  static String defaultBaseUrl() {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return 'http://127.0.0.1:8000';
    }
    return 'https://solaris-headlines-targeted-dive.trycloudflare.com';
  }

  static Future<String> _detectBestHost() async {
    const candidates = [
      'https://solaris-headlines-targeted-dive.trycloudflare.com',
      'http://192.168.1.164:8000',
      'http://127.0.0.1:8000',
      'http://10.177.13.70:8000',
    ];
    for (final host in candidates) {
      try {
        final res = await http.get(
          Uri.parse('$host/health'),
          headers: {'Bypass-Tunnel-Reminder': 'true'},
        ).timeout(const Duration(milliseconds: 1800));
        if (res.statusCode == 200) {
          return host;
        }
      } catch (_) {}
    }
    return 'https://solaris-headlines-targeted-dive.trycloudflare.com';
  }

  String _apiBaseUrl = defaultBaseUrl();
  String? _token;
  AppUser? _user;
  String _languageCode = 'en';
  List<Subsystem> _subsystems = [];
  StudentHomeData? _studentHome;
  AdminDashboardData? _adminDashboard;

  bool _isBootstrapping = true;
  bool _isLoading = false;
  String? _error;

  String get apiBaseUrl => _apiBaseUrl;
  String? get token => _token;
  AppUser? get user => _user;
  String get languageCode => _languageCode;
  List<Subsystem> get subsystems => _subsystems;
  StudentHomeData? get studentHome => _studentHome;
  AdminDashboardData? get adminDashboard => _adminDashboard;
  bool get isBootstrapping => _isBootstrapping;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _user != null;

  ApiService get api =>
      ApiService(_apiBaseUrl, token: _token, languageCode: _languageCode);

  Future<void> bootstrap() async {
    _isBootstrapping = true;
    notifyListeners();

    final minSplashDelay = Future<void>.delayed(const Duration(milliseconds: 1200));

    final prefs = await SharedPreferences.getInstance();
    final isDesktopOrWeb = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isDesktopOrWeb) {
      _apiBaseUrl = 'http://127.0.0.1:8000';
    } else {
      _apiBaseUrl = await _detectBestHost();
    }
    _token = prefs.getString('auth_token');
    _languageCode = prefs.getString('app_language') ?? 'en';
    await prefs.setString(kPrefApiBaseUrl, _apiBaseUrl);

    try {
      await loadSubsystems();
      if (_token != null && _token!.isNotEmpty) {
        _user = await api.getMe();
        await refreshDashboard();
      }
    } catch (_) {
      // Token expired or backend temporarily offline; fall back to Auth screen
      if (_user == null) {
        _token = null;
      }
    } finally {
      await minSplashDelay;
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> setLanguage(String code) async {
    if (code != 'en' && code != 'fr') return;
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', code);
    notifyListeners();
  }

  Future<void> setApiBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    _apiBaseUrl = baseUrl.trim();
    await prefs.setString(kPrefApiBaseUrl, _apiBaseUrl);
    await loadSubsystems();
    notifyListeners();
  }

  Future<void> loadSubsystems() async {
    try {
      _subsystems = await api.getSubsystems();
    } catch (_) {
      // Fallback Cameroon list if offline before API connects
      if (_subsystems.isEmpty) {
        _subsystems = _fallbackCameroonSubsystems();
      }
    }
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    _setBusy(true);
    try {
      final (newToken, newUser) = await api.register(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
      );
      _apiBaseUrl = api.baseUrl;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefApiBaseUrl, _apiBaseUrl);
      await _persistSession(newToken, newUser);
      _setBusy(false);
      loadSubsystems();
      refreshDashboard();
    } catch (e) {
      _setBusy(false);
      rethrow;
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _setBusy(true);
    try {
      final (newToken, newUser) = await api.login(
        email: email,
        password: password,
      );
      _apiBaseUrl = api.baseUrl;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefApiBaseUrl, _apiBaseUrl);
      await _persistSession(newToken, newUser);
      _setBusy(false);
      loadSubsystems();
      refreshDashboard();
    } catch (e) {
      _setBusy(false);
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _token = null;
    _user = null;
    _studentHome = null;
    _adminDashboard = null;
    _error = null;
    notifyListeners();
  }

  Future<void> submitQuestionnaire({
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
    _setBusy(true);
    try {
      await api.saveQuestionnaire(
        fullName: fullName,
        subsystemId: subsystemId,
        classId: classId,
        age: age,
        favouriteSubject: favouriteSubject,
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
      );
      _user = await api.getMe();
      await BackgroundService.scheduleDailyReminder(
        hour: reminderHour,
        minute: reminderMinute,
      );
      await refreshDashboard();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshDashboard() async {
    if (!isAuthenticated) return;
    _error = null;
    try {
      if (_user!.isAdmin) {
        _adminDashboard = await api.getAdminDashboard();
      } else {
        _studentHome = await api.getStudentHome();
        final home = _studentHome!;
        final dailySummary = home.todayTopics.isNotEmpty
            ? 'Today: ${home.todayTopics.map((t) => '${t.subjectName} (${t.topicTitle})').join(', ')}'
            : null;
        final weeklySummary = home.weeklyTopics.isNotEmpty
            ? 'This week: ${home.weeklyTopics.map((t) => '${t.subjectName}: ${t.topicTitle}').take(3).join('; ')}'
            : null;
        await BackgroundService.scheduleDailyReminder(
          hour: home.profile.reminderHour,
          minute: home.profile.reminderMinute,
          customBody: dailySummary,
        );
        await BackgroundService.scheduleSundayWeeklyReminder(
          customBody: weeklySummary,
        );
        await BackgroundService.enablePeriodicBackgroundSync();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> updateTopicProgress({
    required int progressionId,
    required String status,
    required String understandingLevel,
    int? quizScore,
    String? weaknessNotes,
  }) async {
    try {
      _studentHome = await api.updateTopicProgress(
        progressionId: progressionId,
        status: status,
        understandingLevel: understandingLevel,
        quizScore: quizScore,
        weaknessNotes: weaknessNotes,
      );
      notifyListeners();
    } catch (_) {
      await refreshDashboard();
    }
  }

  Future<void> updateAccountProfile({
    String? fullName,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    _setBusy(true);
    try {
      _user = await api.updateProfile(
        fullName: fullName,
        email: email,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      await refreshDashboard();
    } finally {
      _setBusy(false);
    }
  }

  Future<Map<String, dynamic>> uploadCurriculumFiles(
    List<({String name, List<int> bytes})> files, {
    bool refresh = true,
  }) async {
    final result = await api.uploadCurriculumFiles(files: files);
    if (refresh) {
      await refreshDashboard();
    }
    return result;
  }

  Future<Map<String, dynamic>> uploadProgramsFiles(
    List<({String name, List<int> bytes})> files,
  ) async {
    final result = await api.uploadProgramsFiles(files: files);
    await refreshDashboard();
    return result;
  }

  Future<Map<String, dynamic>> uploadProgressionsFiles(
    List<({String name, List<int> bytes})> files,
  ) async {
    final result = await api.uploadProgressionsFiles(files: files);
    await refreshDashboard();
    return result;
  }

  Future<void> createOfficialProgression({
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
    await api.createOfficialProgression(
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
    await refreshDashboard();
  }

  Future<void> deleteOfficialProgression(int progressionId) async {
    await api.deleteOfficialProgression(progressionId);
    await refreshDashboard();
  }

  Future<void> deleteUploadedFolder(String folderName) async {
    _setBusy(true);
    try {
      await api.deleteUploadedFolder(folderName);
      await refreshDashboard();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateUserStatus(int userId, bool isActive) async {
    _setBusy(true);
    try {
      await api.updateUserStatus(userId, isActive);
      await refreshDashboard();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> createAdminUser({
    required String fullName,
    required String email,
    required String password,
    String role = 'student',
    int? subsystemId,
    int? classId,
  }) async {
    _setBusy(true);
    try {
      await api.createAdminUser(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
        subsystemId: subsystemId,
        classId: classId,
      );
      await refreshDashboard();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteAdminUser(int userId) async {
    _setBusy(true);
    try {
      await api.deleteAdminUser(userId);
      await refreshDashboard();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _persistSession(String token, AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    _token = token;
    _user = user;
    _apiBaseUrl = api.baseUrl;
    await prefs.setString(kPrefApiBaseUrl, _apiBaseUrl);
    await prefs.setString('auth_token', token);
    await prefs.setInt(kPrefStudentId, user.id);
  }

  void _setBusy(bool busy) {
    _isLoading = busy;
    if (busy) _error = null;
    notifyListeners();
  }

  List<Subsystem> _fallbackCameroonSubsystems() {
    return [
      Subsystem(
        id: 1,
        code: 'en',
        name: 'English Subsystem',
        description: 'Form 1 to Upper Sixth',
        classes: [
          SchoolClass(id: 1, subsystemId: 1, name: 'Form 1', levelOrder: 1),
          SchoolClass(id: 2, subsystemId: 1, name: 'Form 2', levelOrder: 2),
          SchoolClass(id: 3, subsystemId: 1, name: 'Form 3', levelOrder: 3),
          SchoolClass(id: 4, subsystemId: 1, name: 'Form 4', levelOrder: 4),
          SchoolClass(id: 5, subsystemId: 1, name: 'Form 5', levelOrder: 5),
          SchoolClass(id: 6, subsystemId: 1, name: 'Lower Sixth', levelOrder: 6),
          SchoolClass(id: 7, subsystemId: 1, name: 'Upper Sixth', levelOrder: 7),
        ],
      ),
      Subsystem(
        id: 2,
        code: 'fr',
        name: 'French Subsystem',
        description: '6eme to Terminale',
        classes: [
          SchoolClass(id: 8, subsystemId: 2, name: '6eme', levelOrder: 1),
          SchoolClass(id: 9, subsystemId: 2, name: '5eme', levelOrder: 2),
          SchoolClass(id: 10, subsystemId: 2, name: '4eme', levelOrder: 3),
          SchoolClass(id: 11, subsystemId: 2, name: '3eme', levelOrder: 4),
          SchoolClass(id: 12, subsystemId: 2, name: 'Seconde', levelOrder: 5),
          SchoolClass(id: 13, subsystemId: 2, name: 'Premiere', levelOrder: 6),
          SchoolClass(id: 14, subsystemId: 2, name: 'Terminale', levelOrder: 7),
        ],
      ),
    ];
  }
}
