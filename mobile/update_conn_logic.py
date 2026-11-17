with open('mobile/lib/services/api_service.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

# 1. Change final String baseUrl to String baseUrl
text = text.replace('final String baseUrl;', 'String baseUrl;')

# 2. Add auto-fallback in register and login
old_reg_login = """  Future<(String, AppUser)> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await http
        .post(
          _uri('/auth/register'),
          headers: _headers,
          body: jsonEncode({
            'full_name': fullName,
            'email': email,
            'password': password,
            'role': role,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final map = _decodeMap(res);
    return (
      map['access_token'] as String,
      AppUser.fromJson(map['user'] as Map<String, dynamic>),
    );
  }

  Future<(String, AppUser)> login({
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          _uri('/auth/login'),
          headers: _headers,
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final map = _decodeMap(res);
    return (
      map['access_token'] as String,
      AppUser.fromJson(map['user'] as Map<String, dynamic>),
    );
  }"""

new_reg_login = """  Future<(String, AppUser)> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final res = await http
          .post(
            _uri('/auth/register'),
            headers: _headers,
            body: jsonEncode({
              'full_name': fullName,
              'email': email,
              'password': password,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final map = _decodeMap(res);
      return (
        map['access_token'] as String,
        AppUser.fromJson(map['user'] as Map<String, dynamic>),
      );
    } catch (e) {
      if (baseUrl.contains('127.0.0.1') && !kIsWeb) {
        baseUrl = 'http://192.168.1.148:8000';
        final res = await http
            .post(
              _uri('/auth/register'),
              headers: _headers,
              body: jsonEncode({
                'full_name': fullName,
                'email': email,
                'password': password,
                'role': role,
              }),
            )
            .timeout(const Duration(seconds: 10));
        final map = _decodeMap(res);
        return (
          map['access_token'] as String,
          AppUser.fromJson(map['user'] as Map<String, dynamic>),
        );
      }
      rethrow;
    }
  }

  Future<(String, AppUser)> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            _uri('/auth/login'),
            headers: _headers,
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final map = _decodeMap(res);
      return (
        map['access_token'] as String,
        AppUser.fromJson(map['user'] as Map<String, dynamic>),
      );
    } catch (e) {
      if (baseUrl.contains('127.0.0.1') && !kIsWeb) {
        baseUrl = 'http://192.168.1.148:8000';
        final res = await http
            .post(
              _uri('/auth/login'),
              headers: _headers,
              body: jsonEncode({
                'email': email,
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 10));
        final map = _decodeMap(res);
        return (
          map['access_token'] as String,
          AppUser.fromJson(map['user'] as Map<String, dynamic>),
        );
      }
      rethrow;
    }
  }"""

assert old_reg_login in text, "old_reg_login not found in api_service.dart"
text = text.replace(old_reg_login, new_reg_login)

with open('mobile/lib/services/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print("Updated api_service.dart with auto-fallback to 192.168.1.148 successfully!")

# Update study_provider.dart defaultBaseUrl
with open('mobile/lib/providers/study_provider.dart', 'r', encoding='utf-8') as f:
    stext = f.read().replace('\r\n', '\n')

old_base_url = """  static String defaultBaseUrl() {
    // When connected via USB with `adb reverse tcp:8000 tcp:8000`, 127.0.0.1 forwards directly to the PC backend.
    // For wireless Wi-Fi without USB, 192.168.1.148:8000 or the in-app server settings dialog can be used.
    return 'http://127.0.0.1:8000';
  }"""

new_base_url = """  static String defaultBaseUrl() {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // On physical mobile devices, default to PC Wi-Fi IP so it works wirelessly without requiring USB
    return 'http://192.168.1.148:8000';
  }"""

assert old_base_url in stext, "old_base_url not found in study_provider.dart"
stext = stext.replace(old_base_url, new_base_url)

old_boot = """    final prefs = await SharedPreferences.getInstance();
    _apiBaseUrl = prefs.getString(kPrefApiBaseUrl) ?? defaultBaseUrl();"""

new_boot = """    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(kPrefApiBaseUrl);
    if (savedUrl == null || (!kIsWeb && savedUrl.contains('127.0.0.1'))) {
      _apiBaseUrl = defaultBaseUrl();
    } else {
      _apiBaseUrl = savedUrl;
    }"""

assert old_boot in stext, "old_boot not found in study_provider.dart"
stext = stext.replace(old_boot, new_boot)

with open('mobile/lib/providers/study_provider.dart', 'w', encoding='utf-8') as f:
    f.write(stext)
print("Updated study_provider.dart defaultBaseUrl successfully!")

