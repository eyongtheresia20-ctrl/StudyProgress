import 'dart:convert';

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:excel/excel.dart';

import 'package:http/http.dart' as http;

import '../models/study_models.dart';

import 'supabase_cloud_service.dart';

/// Everything the admin and the AI tutor need, talking ONLY to Supabase

/// (database) and Gemini (AI). No laptop, no tunnel, no backend server.

class CloudExtras {
  static const String _url = SupabaseCloudService.supabaseUrl;

  static const String _key = SupabaseCloudService.supabaseAnonKey;

  static String get _gKey => SupabaseCloudService.geminiApiKey;

  static const List<String> _models = [
    SupabaseCloudService.geminiModel,

    'gemini-3.5-flash-lite',
  ];

  final SupabaseCloudService _cloud = SupabaseCloudService();

  static final Map<int, Map<String, String>> _ctxCache = {};

  Map<String, String> get _h => {
    'apikey': _key,

    'Authorization': 'Bearer $_key',

    'Content-Type': 'application/json',

    'Accept': 'application/json',

    'Prefer': 'return=representation',
  };

  Uri _u(String path, [Map<String, dynamic>? q]) {
    final qs = (q == null || q.isEmpty)
        ? ''
        : '?${q.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}').join('&')}';

    return Uri.parse('$_url/rest/v1$path$qs');
  }

  Future<List<dynamic>> _list(String path, Map<String, dynamic> q) async {
    final r = await http.get(_u(path, q), headers: _h);

    if (r.statusCode != 200) {
      throw Exception('Supabase ${r.statusCode}: ${r.body}');
    }

    return jsonDecode(r.body) as List<dynamic>;
  }

  Future<int> _count(
    String table, [
    Map<String, dynamic> filters = const {},
  ]) async {
    final r = await http.get(
      _u('/$table', {'select': 'id', ...filters}),

      headers: {..._h, 'Prefer': 'count=exact', 'Range': '0-0'},
    );

    final cr = r.headers['content-range'] ?? '';

    final slash = cr.lastIndexOf('/');

    if (slash >= 0) return int.tryParse(cr.substring(slash + 1)) ?? 0;

    return 0;
  }

  Future<(Map<int, String>, Map<int, String>)> _names() async {
    final subs = await _list('/subsystems', {'select': 'id,name'});

    final cls = await _list('/classes', {'select': 'id,name'});

    return (
      {for (final s in subs) (s['id'] as num).toInt(): s['name'] as String},

      {for (final c in cls) (c['id'] as num).toInt(): c['name'] as String},
    );
  }

  // ===================================================================

  // SESSION / PROFILE

  // ===================================================================

  Future<AppUser> getMe({AppUser? current, String? token}) async {
    int? id = current?.id;

    if (id == null && token != null) {
      try {
        final raw = utf8.decode(base64Url.decode(base64Url.normalize(token)));

        id = int.tryParse(raw.split(':')[1]);
      } catch (_) {}
    }

    if (id == null) throw Exception('Session expirée, reconnectez-vous.');

    final rows = await _list('/users', {'id': 'eq.$id', 'select': '*'});

    if (rows.isEmpty) throw Exception('Compte introuvable.');

    final u = rows.first as Map<String, dynamic>;

    if (u['is_active'] == false) {
      throw Exception('Compte désactivé par l\'administrateur.');
    }

    final role = u['role'] as String? ?? 'student';

    var done = true;

    if (role == 'student') {
      final p = await _list('/student_profiles', {
        'user_id': 'eq.$id',
        'select': 'questionnaire_completed',
      });

      done = p.isNotEmpty && (p.first['questionnaire_completed'] == true);
    }

    return AppUser(
      id: id,

      fullName: u['full_name'] as String? ?? '',

      email: u['email'] as String? ?? '',

      role: role,

      questionnaireCompleted: done,
    );
  }

  Future<AppUser> updateProfile({
    required AppUser user,

    String? fullName,

    String? email,

    String? currentPassword,

    String? newPassword,
  }) async {
    final patch = <String, dynamic>{};

    if (fullName != null && fullName.trim().isNotEmpty) {
      patch['full_name'] = fullName.trim();
    }

    if (email != null && email.trim().isNotEmpty) {
      final clean = email.trim().toLowerCase();

      if (clean != user.email.toLowerCase()) {
        final dup = await _list('/users', {
          'email': 'eq.$clean',
          'select': 'id',
        });

        if (dup.isNotEmpty) throw Exception('Cet email est déjà utilisé.');

        patch['email'] = clean;
      }
    }

    if (newPassword != null && newPassword.isNotEmpty) {
      final rows = await _list('/users', {
        'id': 'eq.${user.id}',
        'select': 'password_hash',
      });

      final stored = rows.isEmpty
          ? ''
          : (rows.first['password_hash'] as String? ?? '');

      if (!SupabaseCloudService.verifyPassword(currentPassword ?? '', stored)) {
        throw Exception('Mot de passe actuel incorrect.');
      }

      patch['password_hash'] = SupabaseCloudService.hashPassword(newPassword);
    }

    if (patch.isNotEmpty) {
      final r = await http.patch(
        _u('/users', {'id': 'eq.${user.id}'}),

        headers: _h,
        body: jsonEncode(patch),
      );

      if (r.statusCode >= 300) throw Exception('Erreur mise à jour: ${r.body}');
    }

    return getMe(current: user);
  }

  // ===================================================================

  // ADMIN: dashboard, users, progressions

  // ===================================================================

  Future<List<Map<String, dynamic>>> _usersWithProfile({
    String? role,
    int limit = 500,
  }) async {
    final names = await _names();

    final q = <String, dynamic>{
      'select': 'id,full_name,email,role,is_active,created_at',

      'order': 'created_at.desc',

      'limit': '$limit',
    };

    if (role != null) q['role'] = 'eq.$role';

    final users = await _list('/users', q);

    final profs = await _list('/student_profiles', {
      'select': 'user_id,subsystem_id,class_id,questionnaire_completed',

      'limit': '5000',
    });

    final byUser = {
      for (final p in profs)
        (p['user_id'] as num).toInt(): p as Map<String, dynamic>,
    };

    return users.map<Map<String, dynamic>>((u) {
      final id = (u['id'] as num).toInt();

      final p = byUser[id];

      final sid = (p?['subsystem_id'] as num?)?.toInt();

      final cid = (p?['class_id'] as num?)?.toInt();

      return {
        'id': id,

        'full_name': u['full_name'],

        'email': u['email'],

        'role': u['role'],

        'is_active': u['is_active'] != false,

        'subsystem_id': sid,

        'subsystem_name': sid != null ? names.$1[sid] : null,

        'class_id': cid,

        'class_name': cid != null ? names.$2[cid] : null,

        'questionnaire_completed': p?['questionnaire_completed'] == true,

        'created_at': u['created_at'],
      };
    }).toList();
  }

  OfficialProgression _prog(
    Map<String, dynamic> e, {
    Map<int, String>? subs,
    Map<int, String>? cls,
  }) {
    final sid = (e['subsystem_id'] as num).toInt();

    final cid = (e['class_id'] as num).toInt();

    return OfficialProgression(
      id: (e['id'] as num).toInt(),

      subsystemId: sid,

      subsystemName: subs?[sid],

      classId: cid,

      className: cls?[cid],

      subjectName: e['subject_name'] as String? ?? '',

      topicTitle: e['topic_title'] as String? ?? '',

      subtopics: e['subtopics'] as String?,

      weekNumber: (e['week_number'] as num?)?.toInt() ?? 1,

      startDate: e['start_date'] as String? ?? '',

      endDate: e['end_date'] as String? ?? '',

      studyDays: e['study_days'] as String?,

      studentStatus: 'not_started',

      understandingLevel: 'none',
    );
  }

  Future<AdminDashboardData> getAdminDashboard(AppUser admin) async {
    final names = await _names();

    final students = await _usersWithProfile(role: 'student', limit: 60);

    final progs = await _list('/official_progressions', {
      'order': 'id.desc',
      'limit': '40',
    });

    final logs = await _list('/uploaded_folder_logs', {
      'order': 'id.desc',
      'limit': '400',
    });

    final folders = <String, Map<String, dynamic>>{};

    for (final l in logs) {
      final name = l['folder_name'] as String? ?? '';

      final f = folders.putIfAbsent(
        name,
        () => {
          'folder_name': name,

          'files_count': 0,

          'topics_added': 0,

          'last_uploaded_at': l['created_at'] ?? '',
        },
      );

      f['files_count'] =
          (f['files_count'] as int) +
          ((l['files_count'] as num?)?.toInt() ?? 0);

      f['topics_added'] =
          (f['topics_added'] as int) +
          ((l['topics_added'] as num?)?.toInt() ?? 0);
    }

    return AdminDashboardData(
      admin: admin,

      subsystemsCount: names.$1.length,

      classesCount: names.$2.length,

      studentsCount: await _count('users', {'role': 'eq.student'}),

      progressionsCount: await _count('official_progressions'),

      programTopicsCount: await _count('program_topics'),

      recentStudents: students,

      progressions: progs
          .map(
            (e) =>
                _prog(e as Map<String, dynamic>, subs: names.$1, cls: names.$2),
          )
          .toList(),

      uploadedFolders: folders.values.take(25).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> getAdminUsers() => _usersWithProfile();

  Future<Map<String, dynamic>> createAdminUser({
    required String fullName,

    required String email,

    required String password,

    String role = 'student',

    int? subsystemId,

    int? classId,
  }) async {
    final clean = email.trim().toLowerCase();

    final dup = await _list('/users', {'email': 'eq.$clean', 'select': 'id'});

    if (dup.isNotEmpty) throw Exception('Cet email est déjà enregistré.');

    final r = await http.post(
      _u('/users'),

      headers: _h,

      body: jsonEncode({
        'full_name': fullName.trim(),

        'email': clean,

        'password_hash': SupabaseCloudService.hashPassword(password),

        'role': role,

        'is_active': true,
      }),
    );

    if (r.statusCode >= 300) throw Exception('Création impossible: ${r.body}');

    final id = ((jsonDecode(r.body) as List).first['id'] as num).toInt();

    if (role == 'student') {
      await http.post(
        _u('/student_profiles'),

        headers: _h,

        body: jsonEncode({
          'user_id': id,

          'subsystem_id': subsystemId,

          'class_id': classId,

          'questionnaire_completed': false,
        }),
      );
    }

    return {
      'id': id,
      'full_name': fullName.trim(),
      'email': clean,
      'role': role,
      'is_active': true,
    };
  }

  Future<Map<String, dynamic>> updateUserStatus(
    int userId,
    bool isActive,
  ) async {
    final r = await http.patch(
      _u('/users', {'id': 'eq.$userId'}),

      headers: _h,
      body: jsonEncode({'is_active': isActive}),
    );

    if (r.statusCode >= 300)
      throw Exception('Mise à jour impossible: ${r.body}');

    return {'id': userId, 'is_active': isActive};
  }

  Future<void> deleteAdminUser(int userId) async {
    final r = await http.delete(
      _u('/users', {'id': 'eq.$userId'}),
      headers: _h,
    );

    if (r.statusCode >= 300)
      throw Exception('Suppression impossible: ${r.body}');
  }

  Future<OfficialProgression> createOfficialProgression({
    required int adminId,

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
    final s = _parseDate(startDate);

    final e = _parseDate(endDate);

    if (s == null || e == null) throw Exception('Dates invalides.');

    if (e.isBefore(s))
      throw Exception('La date de fin doit suivre la date de début.');

    final c = await _list('/classes', {
      'id': 'eq.$classId',
      'subsystem_id': 'eq.$subsystemId',
      'select': 'id',
    });

    if (c.isEmpty) {
      throw Exception('Cette classe n\'appartient pas au sous-système choisi.');
    }

    final r = await http.post(
      _u('/official_progressions'),

      headers: _h,

      body: jsonEncode({
        'subsystem_id': subsystemId,

        'class_id': classId,

        'subject_name': subjectName.trim(),

        'topic_title': topicTitle.trim(),

        'subtopics': subtopics,

        'week_number': weekNumber,

        'start_date': _iso(s),

        'end_date': _iso(e),

        'study_days': studyDays,

        'created_by': adminId,
      }),
    );

    if (r.statusCode >= 300) throw Exception('Création impossible: ${r.body}');

    return _prog((jsonDecode(r.body) as List).first as Map<String, dynamic>);
  }

  Future<void> deleteOfficialProgression(int id) async {
    final r = await http.delete(
      _u('/official_progressions', {'id': 'eq.$id'}),
      headers: _h,
    );

    if (r.statusCode >= 300)
      throw Exception('Suppression impossible: ${r.body}');
  }

  Future<void> deleteUploadedFolder(String folderName) async {
    final r = await http.delete(
      _u('/uploaded_folder_logs', {'folder_name': 'eq.${folderName.trim()}'}),

      headers: _h,
    );

    if (r.statusCode >= 300)
      throw Exception('Suppression impossible: ${r.body}');
  }

  String programTemplate() =>
      'subsystem,class_name,subject,topic,subtopics\n'
      'English Subsystem,Form 5,Mathematics,Matrices & Operations,Addition and matrix multiplication\n'
      'English Subsystem,Form 5,Physics,Linear Motion,Speed velocity and acceleration\n'
      'French Subsystem,3eme,Mathematiques,Equations du 1er degre,Developpement et factorisation\n';

  String progressionTemplate() {
    final today = DateTime.now();

    final end = today.add(const Duration(days: 3));

    final t = _iso(today), e = _iso(end);

    final t2 = _iso(today.add(const Duration(days: 1)));

    final e2 = _iso(end.add(const Duration(days: 2)));

    return 'subsystem,class_name,subject,topic,subtopics,week_number,start_date,end_date,study_days\n'
        'English Subsystem,Form 5,Mathematics,Matrices & Operations,Addition and matrix multiplication,1,$t,$e,Mon - Wed\n'
        'English Subsystem,Form 5,Physics,Linear Motion,Speed velocity and acceleration,1,$t2,$e2,Thu - Sat\n'
        'French Subsystem,3eme,Mathematiques,Equations du 1er degre,Developpement et factorisation,1,$t,$e,Lun - Mer\n';
  }

  // ===================================================================

  // ADMIN: file import (CSV / JSON / XLSX / ZIP) straight into Supabase

  // ===================================================================

  static const Map<String, String> _acc = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',

    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  static final RegExp _alnum = RegExp(r'[a-z0-9]');

  static String _norm(String s) {
    final b = StringBuffer();

    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);

      final m = _acc[ch] ?? ch;

      if (_alnum.hasMatch(m)) b.write(m);
    }

    return b.toString();
  }

  static const Map<String, String> _classAlias = {
    'f1': 'form1',
    'f2': 'form2',
    'f3': 'form3',
    'f4': 'form4',
    'f5': 'form5',

    'ls': 'lowersixth',
    'us': 'uppersixth',
    'lowersixthform': 'lowersixth',

    'uppersixthform': 'uppersixth',

    '6e': '6eme',
    'sixieme': '6eme',
    '5e': '5eme',
    'cinquieme': '5eme',

    '4e': '4eme',
    'quatrieme': '4eme',
    '3e': '3eme',
    'troisieme': '3eme',

    '2nde': 'seconde',
    '2nd': 'seconde',
    '1ere': 'premiere',
    '1re': 'premiere',

    'tle': 'terminale',
  };

  DateTime? _parseDate(String raw) {
    final s = raw.trim();

    if (s.isEmpty) return null;

    final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);

    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);

    if (dmy != null) {
      return DateTime(
        int.parse(dmy.group(3)!),
        int.parse(dmy.group(2)!),
        int.parse(dmy.group(1)!),
      );
    }

    final n = double.tryParse(s);

    if (n != null && n > 20000 && n < 80000) {
      return DateTime(1899, 12, 30).add(Duration(days: n.floor()));
    }

    return null;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<List<String>> _parseCsv(String text) {
    var t = text;

    if (t.startsWith('\uFEFF')) t = t.substring(1);

    final first = t.split('\n').first;

    final commas = ','.allMatches(first).length;

    final semis = ';'.allMatches(first).length;

    final tabs = '\t'.allMatches(first).length;

    final delim = (semis > commas && semis >= tabs)
        ? ';'
        : (tabs > commas ? '\t' : ',');

    final rows = <List<String>>[];

    var row = <String>[];

    final field = StringBuffer();

    var inQ = false;

    for (var i = 0; i < t.length; i++) {
      final c = t[i];

      if (inQ) {
        if (c == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            field.write('"');

            i++;
          } else {
            inQ = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQ = true;
      } else if (c == delim) {
        row.add(field.toString());

        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;

        row.add(field.toString());

        field.clear();

        if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);

        row = <String>[];
      } else {
        field.write(c);
      }
    }

    row.add(field.toString());

    if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);

    return rows;
  }

  List<Map<String, String>> _rowsToMaps(List<List<String>> table) {
    if (table.length < 2) return [];

    final header = table.first.map(_norm).toList();

    final out = <Map<String, String>>[];

    for (final r in table.skip(1)) {
      final m = <String, String>{};

      for (var i = 0; i < header.length && i < r.length; i++) {
        if (header[i].isNotEmpty) m[header[i]] = r[i].trim();
      }

      if (m.values.any((v) => v.isNotEmpty)) out.add(m);
    }

    return out;
  }

  String _cellText(dynamic cell) {
    final v = cell?.value;

    if (v == null) return '';

    try {
      if (v is DateCellValue) {
        return _iso(DateTime(v.year, v.month, v.day));
      }

      if (v is DateTimeCellValue) {
        return _iso(DateTime(v.year, v.month, v.day));
      }

      final inner = (v as dynamic).value;

      if (inner is String) return inner;

      if (inner == null) return v.toString();

      try {
        return (inner as dynamic).toPlainText() as String;
      } catch (_) {
        return inner.toString();
      }
    } catch (_) {
      return v.toString();
    }
  }

  List<Map<String, String>> _parseFile(String name, List<int> bytes) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.csv') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.tsv')) {
      return _rowsToMaps(_parseCsv(utf8.decode(bytes, allowMalformed: true)));
    }

    if (lower.endsWith('.json')) {
      final d = jsonDecode(utf8.decode(bytes, allowMalformed: true));

      List<dynamic>? list;

      if (d is List) {
        list = d;
      } else if (d is Map) {
        for (final v in d.values) {
          if (v is List) {
            list = v;

            break;
          }
        }
      }

      if (list == null) throw Exception('JSON: aucune liste de lignes trouvée');

      return list.whereType<Map>().map((m) {
        return <String, String>{
          for (final e in m.entries)
            _norm(e.key.toString()): e.value?.toString().trim() ?? '',
        };
      }).toList();
    }

    if (lower.endsWith('.xlsx')) {
      final excel = Excel.decodeBytes(Uint8List.fromList(bytes));

      final out = <Map<String, String>>[];

      for (final sheet in excel.tables.values) {
        final table = sheet.rows
            .map((r) => r.map((c) => _cellText(c).trim()).toList())
            .where((r) => r.any((x) => x.isNotEmpty))
            .toList();

        out.addAll(_rowsToMaps(table));
      }

      return out;
    }

    if (lower.endsWith('.xls')) {
      throw Exception(
        'format .xls non supporté — enregistrez en .xlsx ou .csv',
      );
    }

    throw Exception('format non supporté');
  }

  List<(String, List<int>)> _expand(
    List<({String name, List<int> bytes})> files,
    List<String> errors,
  ) {
    final out = <(String, List<int>)>[];

    void add(String name, List<int> bytes, String prefix) {
      final full = (prefix.isEmpty ? name : '$prefix/$name').replaceAll(
        '\\',
        '/',
      );

      if (full.contains('__MACOSX') || full.split('/').last.startsWith('.'))
        return;

      if (full.toLowerCase().endsWith('.zip')) {
        try {
          final arc = ZipDecoder().decodeBytes(bytes);

          for (final f in arc) {
            if (f.isFile) {
              add(
                f.name,
                (f.content as List).cast<int>(),
                full.substring(0, full.length - 4),
              );
            }
          }
        } catch (e) {
          errors.add('$full: zip illisible ($e)');
        }
      } else {
        out.add((full, bytes));
      }
    }

    for (final f in files) {
      add(f.name, f.bytes, '');
    }

    return out;
  }

  String _f(Map<String, String> r, List<String> keys) {
    for (final k in keys) {
      final v = r[k];

      if (v != null && v.trim().isNotEmpty) return v.trim();
    }

    return '';
  }

  /// mode: 'progressions' | 'programs' | 'curriculum'

  Future<Map<String, dynamic>> importFiles({
    required List<({String name, List<int> bytes})> files,

    required String mode,

    required int adminId,
  }) async {
    final errors = <String>[];

    final subsRows = await _list('/subsystems', {'select': 'id,code,name'});

    final clsRows = await _list('/classes', {'select': 'id,subsystem_id,name'});

    int? subFromText(String s) {
      final n = _norm(s);

      if (n.isEmpty) return null;

      for (final r in subsRows) {
        final id = (r['id'] as num).toInt();

        if (n == _norm(r['code'] as String) || n == _norm(r['name'] as String))
          return id;
      }

      if (n.contains('english') || n.contains('anglo')) {
        return (subsRows.firstWhere(
                  (r) => r['code'] == 'en',
                  orElse: () => {'id': null},
                )['id']
                as num?)
            ?.toInt();
      }

      if (n.contains('french') ||
          n.contains('franco') ||
          n.contains('francais')) {
        return (subsRows.firstWhere(
                  (r) => r['code'] == 'fr',
                  orElse: () => {'id': null},
                )['id']
                as num?)
            ?.toInt();
      }

      return null;
    }

    int? clsFromText(int subId, String s) {
      var n = _norm(s);

      n = _classAlias[n] ?? n;

      for (final r in clsRows) {
        if ((r['subsystem_id'] as num).toInt() == subId &&
            _norm(r['name'] as String) == n) {
          return (r['id'] as num).toInt();
        }
      }

      return null;
    }

    int? clsAnySub(String s) {
      var n = _norm(s);

      n = _classAlias[n] ?? n;

      for (final r in clsRows) {
        if (_norm(r['name'] as String) == n) return (r['id'] as num).toInt();
      }

      return null;
    }

    final expanded = _expand(files, errors);

    final progRows = <Map<String, dynamic>>[];

    final topicRows = <Map<String, dynamic>>[];

    final perFolderFiles = <String, int>{};

    final perFolderTopics = <String, int>{};

    var skipped = errors.length;

    for (final (path, bytes) in expanded) {
      final lower = path.toLowerCase();

      if (!(lower.endsWith('.csv') ||
          lower.endsWith('.json') ||
          lower.endsWith('.xlsx') ||
          lower.endsWith('.xls') ||
          lower.endsWith('.txt') ||
          lower.endsWith('.tsv'))) {
        continue; // pdf / docx etc.: nothing to import as rows
      }

      final parts = path.split('/');

      final folder = parts.length > 1 ? parts.first : path;

      perFolderFiles[folder] = (perFolderFiles[folder] ?? 0) + 1;

      List<Map<String, String>> rows;

      try {
        rows = _parseFile(path, bytes);
      } catch (e) {
        skipped++;

        errors.add('$path: $e');

        continue;
      }

      int? pathSub;

      int? pathCls;

      for (final seg in parts.take(parts.length - 1)) {
        pathSub ??= subFromText(seg);
      }

      final fileBase = parts.last.contains('.')
          ? parts.last.substring(0, parts.last.lastIndexOf('.'))
          : parts.last;

      for (final seg in parts) {
        final cand = seg.contains('.')
            ? seg.substring(0, seg.lastIndexOf('.'))
            : seg;

        pathCls ??= clsAnySub(cand);
      }

      var idx = 0;

      for (final r in rows) {
        idx++;

        final subId =
            subFromText(
              _f(r, [
                'subsystem',
                'subsystemname',
                'subsystemcode',
                'soussysteme',
              ]),
            ) ??
            pathSub;

        if (subId == null) {
          skipped++;

          errors.add('$path ligne $idx: sous-système inconnu');

          continue;
        }

        final clsText = _f(r, [
          'classname',
          'class',
          'classe',
          'level',
          'niveau',
        ]);

        final clsId =
            (clsText.isNotEmpty ? clsFromText(subId, clsText) : null) ??
            (pathCls != null &&
                    clsRows.any(
                      (c) =>
                          (c['id'] as num).toInt() == pathCls &&
                          (c['subsystem_id'] as num).toInt() == subId,
                    )
                ? pathCls
                : null);

        if (clsId == null) {
          skipped++;

          errors.add('$path ligne $idx: classe inconnue "$clsText"');

          continue;
        }

        var subject = _f(r, [
          'subject',
          'subjectname',
          'matiere',
          'discipline',
        ]);

        if (subject.isEmpty) subject = fileBase;

        final topic = _f(r, [
          'topic',
          'topictitle',
          'chapter',
          'chapitre',
          'lesson',
          'lecon',
          'title',
          'titre',
          'theme',
          'intitule',
        ]);

        final subtopics = _f(r, [
          'subtopics',
          'subtopic',
          'details',
          'content',
          'contenu',
          'description',
        ]);

        if (subject.isEmpty || topic.isEmpty) {
          skipped++;

          errors.add('$path ligne $idx: matière ou chapitre manquant');

          continue;
        }

        final sd = _parseDate(
          _f(r, ['startdate', 'from', 'fromdate', 'debut', 'datedebut']),
        );

        final ed = _parseDate(
          _f(r, ['enddate', 'to', 'todate', 'fin', 'datefin']),
        );

        final hasDates = sd != null && ed != null;

        final asProgression =
            mode == 'progressions' || (mode == 'curriculum' && hasDates);

        if (asProgression) {
          if (!hasDates) {
            skipped++;

            errors.add('$path ligne $idx: dates manquantes');

            continue;
          }

          if (ed.isBefore(sd)) {
            skipped++;

            errors.add('$path ligne $idx: date de fin avant la date de début');

            continue;
          }

          final week =
              int.tryParse(_f(r, ['weeknumber', 'week', 'semaine'])) ?? 1;

          final days = _f(r, ['studydays', 'days', 'jours']);

          progRows.add({
            'subsystem_id': subId,

            'class_id': clsId,

            'subject_name': subject.length > 95
                ? subject.substring(0, 95)
                : subject,

            'topic_title': topic.length > 195 ? topic.substring(0, 195) : topic,

            'subtopics': subtopics.isEmpty ? null : subtopics,

            'week_number': week,

            'start_date': _iso(sd),

            'end_date': _iso(ed),

            'study_days': days.isEmpty
                ? 'Mon - Wed'
                : (days.length > 58 ? days.substring(0, 58) : days),

            'created_by': adminId,
          });
        } else {
          topicRows.add({
            'subsystem_id': subId,

            'class_id': clsId,

            'subject_name': subject.length > 95
                ? subject.substring(0, 95)
                : subject,

            'topic_title': topic.length > 195 ? topic.substring(0, 195) : topic,

            'subtopics': subtopics.isEmpty ? null : subtopics,

            'created_by': adminId,
          });
        }

        perFolderTopics[folder] = (perFolderTopics[folder] ?? 0) + 1;
      }
    }

    Future<int> bulk(String table, List<Map<String, dynamic>> rows) async {
      var ok = 0;

      for (var i = 0; i < rows.length; i += 400) {
        final chunk = rows.sublist(
          i,
          i + 400 > rows.length ? rows.length : i + 400,
        );

        final r = await http.post(
          _u('/$table'),

          headers: {..._h, 'Prefer': 'return=minimal'},
          body: jsonEncode(chunk),
        );

        if (r.statusCode >= 300) {
          skipped += chunk.length;

          errors.add('$table: ${r.body}');
        } else {
          ok += chunk.length;
        }
      }

      return ok;
    }

    final progIns = await bulk('official_progressions', progRows);

    final topicIns = await bulk('program_topics', topicRows);

    if (perFolderFiles.isNotEmpty) {
      await http.post(
        _u('/uploaded_folder_logs'),

        headers: {..._h, 'Prefer': 'return=minimal'},

        body: jsonEncode([
          for (final e in perFolderFiles.entries)
            {
              'folder_name': e.key,

              'files_count': e.value,

              'topics_added': perFolderTopics[e.key] ?? 0,

              'uploaded_by': adminId,
            },
        ]),
      );
    }

    return {
      'inserted_count': progIns + topicIns,

      'skipped_count': skipped,

      'programs_inserted': topicIns,

      'progressions_inserted': progIns,

      'errors': errors.take(15).toList(),
    };
  }

  // ===================================================================

  // AI (Gemini called directly) + history in Supabase

  // ===================================================================

  Future<String> _gemini(
    List<Map<String, dynamic>> parts, {
    bool json = false,
    String? system,
    List<Map<String, dynamic>>? fullContents,
  }) async {
    final body = jsonEncode({
      'contents': fullContents ?? [
        {'role': 'user', 'parts': parts},
      ],

      if (system != null)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },

      if (json) 'generationConfig': {'responseMimeType': 'application/json'},
    });

    Object? last;

    const candidateModels = [
      'gemini-flash-lite-latest',
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-3.1-flash-lite',
    ];

    for (final model in candidateModels) {
      try {
        final r = await http
            .post(
              Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_gKey',
              ),

              headers: {'Content-Type': 'application/json'},

              body: body,
            )
            .timeout(const Duration(seconds: 10));

        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);

          final ps = (d['candidates']?[0]?['content']?['parts'] as List?) ?? [];

          final text = ps.map((p) => p['text']?.toString() ?? '').join();

          if (text.trim().isNotEmpty) {
            _lastModel = model;

            return cleanMathNotation(text);
          }
        }

        last = 'HTTP ${r.statusCode}';
      } catch (e) {
        last = e;
      }
    }

    throw Exception(
      'L\'assistant IA est indisponible pour le moment ($last). Réessayez.',
    );
  }

  String _buildAcademicAnswer({
    required String question,

    String? topicTitle,

    String? subjectName,

    required bool isFr,

    required String studentName,
  }) {
    final qLower = question.toLowerCase().trim();

    if (qLower.contains('biolog')) {
      return isFr
          ? '''# Biologie (Sciences de la Vie)

La **biologie** est la science naturelle qui étudie la vie, les organismes vivants (êtres humains, animaux, végétaux et micro-organismes) ainsi que leurs interactions avec leur environnement.



## Branches fondamentales :

1. **La cytologie (biologie cellulaire)** : Étude de la cellule, unité de base de tout être vivant.

2. **La génétique** : Étude de la transmission des caractères héréditaires (ADN, chromosomes).

3. **La physiologie** : Étude du fonctionnement des organes et des systèmes vivants.

4. **L'écologie** : Étude des relations entre les êtres vivants et leur biotope.



## Notions clés pour les examens MINESEC :

- La cellule animale et la cellule végétale.

- La photosynthèse et la respiration cellulaire.

- Les lois de Mendel et les règles d'hygiène et de santé.'''
          : '''# Biology (Life Science)

**Biology** is the branch of science that studies living organisms, their physical structure, chemical processes, molecular interactions, physiological mechanisms, development, and evolution.



## Major Branches:

1. **Cell Biology (Cytology)**: The study of the basic structural and functional units of life.

2. **Genetics**: The science of heredity, genes, and DNA variation.

3. **Physiology**: How organs and biological systems operate and maintain homeostasis.

4. **Ecology**: How living organisms interact with each other and their environment.



## Key Topics for Cameroon GCE / MINESEC:

- Cell ultra-structure, mitosis, and meiosis.

- Photosynthesis, respiration, and enzymes.

- Nutrition, transport systems, and homeostasis.''';
    }

    if (qLower.contains('chimie') || qLower.contains('chemistry')) {
      return isFr
          ? '''# La Chimie

La **chimie** est la science de la matière : elle étudie la composition, les propriétés, la structure des substances et les transformations chimiques qu'elles subissent.



## Notions essentielles :

- L'atome, les éléments chimiques et la classification périodique.

- Les liaisons chimiques, réactions acido-basiques et réactions d'oxydoréduction.

- Les états de la matière et la stœchiométrie.'''
          : '''# Chemistry

**Chemistry** is the scientific study of the properties and behavior of matter, including the atomic composition, chemical bonding, and reactions between substances.



## Core Concepts:

- Atomic structure, isotopes, and the Periodic Table.

- Acids, bases, redox reactions, and chemical equilibrium.

- Stoichiometry, moles, and gas laws.''';
    }

    if (qLower.contains('physiq') || qLower.contains('physics')) {
      return isFr
          ? '''# La Physique

La **physique** est la science fondamentale qui étudie les lois de l'univers : la matière, le mouvement, l'énergie, les forces, l'espace et le temps.



## Domaines clés :

- La mécanique (mouvement, lois de Newton, gravitation).

- L'électricité et le magnétisme.

- L'optique et la physique nucléaire (radioactivité : ²³⁸₉₂U → ²³⁴₉₀Th + ⁴₂He).'''
          : '''# Physics

**Physics** is the fundamental science that examines the nature and properties of matter and energy, covering mechanics, heat, light and radiation, sound, electricity, magnetism, and atomic structure.



## Core Areas:

- Mechanics (motion, Newton's laws, energy conservation).

- Electricity and electromagnetism.

- Waves, optics, and nuclear physics (radioactivity: ²³⁸₉₂U → ²³⁴₉₀Th + ⁴₂He).''';
    }

    final title = topicTitle != null && topicTitle.isNotEmpty
        ? topicTitle
        : (subjectName ?? (isFr ? 'ce sujet' : 'this topic'));

    return isFr
        ? '''Bonjour $studentName ! Voici l'explication essentielle concernant **$title** :



1. **Définition & Cadre :**

Cette notion s'inscrit au cœur du programme officiel d'enseignement secondaire camerounais (MINESEC). Elle met en jeu les principes théoriques fondamentaux de la discipline.



2. **Méthode d'examen :**

Pour réussir les questions d'évaluation sur ce thème, commencez par poser clairement les définitions et lois fondamentales, posez les données avec leurs unités, et détaillez votre démarche pas à pas.



Posez-moi une question plus spécifique sur un exercice ou un calcul particulier si vous le souhaitez !'''
        : '''Hello $studentName! Here is the core explanation regarding **$title**:



1. **Definition & Context:**

This concept is central to the official secondary curriculum (Cameroon GCE Board / MINESEC). It establishes the fundamental principles and laws governing this subject.



2. **Examination Methodology:**

To achieve top marks on related questions, begin by defining core terms, state applicable laws or equations with units, and structure your steps logically.



Feel free to ask a specific follow-up question or request a solved calculation on this topic!''';
  }

  String _buildFallbackComprehensiveCourse({
    required String cleanTopic,

    required String cleanSubject,

    String? subtopics,

    required int weekNumber,

    required bool isFr,
  }) {
    if (isFr) {
      return '''

# COURS OFFICIEL : $cleanTopic

**Matière :** $cleanSubject | **Cadre :** Programme Officiel MINESEC Cameroun (Semaine $weekNumber)



## 1. Introduction & Objectifs de la leçon

Cette leçon s'inscrit directement dans le programme officiel d'enseignement secondaire camerounais (MINESEC).

Elle vise à faire acquérir à l'élève les compétences fondamentales suivantes :

- Identifier et définir clairement les concepts essentiels liés à **$cleanTopic**.

- Maîtriser le vocabulaire technique, les lois et les mécanismes régissant cette thématique.

- Être capable d'appliquer ces notions dans des exercices types d'examen et des situations concrètes.



## 2. Définitions complètes & Vocabulaire clé

- **$cleanTopic** : Notion centrale du chapitre désignant les processus et principes étudiés dans ce module.

- **Cadre d'application** : Ensemble des conditions méthodologiques et pratiques d'observation et d'analyse.

${subtopics != null && subtopics.isNotEmpty ? '- **Sous-notions au programme** : $subtopics\n' : ''}

## 3. Cadre théorique, Lois, Règles et Formules

Pour maîtriser ce cours, il convient de retenir les règles fondamentales suivantes :

1. **Principe de base** : Tout raisonnement académique s'appuie sur l'analyse méthodique des données et des faits observés.

2. **Méthode d'analyse** : Identifier les variables en jeu, poser les hypothèses et vérifier la cohérence des résultats.

3. **Formalisme académique** : Respecter scrupuleusement les conventions de notation et de terminologie prescrites par l'inspection pédagogique.



## 4. Développement approfondi du cours

### A. Découverte et principes directeurs

L'étude approfondie de **$cleanTopic** met en lumière les articulations logiques indispensables pour comprendre le fonctionnement global de cette matière. Chaque élément observé interagit avec l'ensemble du système.



### B. Analyse détaillée et mécanismes opératoires

Dans le cadre de cette leçon, la démarche consiste à décomposer le problème en étapes élémentaires :

- Première phase : Recueil des données et identification des règles applicables.

- Deuxième phase : Traitement méthodique et formulation des conclusions.

- Troisième phase : Vérification et validation des acquis par l'auto-évaluation.



## 5. Applications concrètes & Exercices d'application résolus

**Exemple type d'examen :**

Expliquer comment appliquer les principes de **$cleanTopic** dans une situation pratique.

**Solution méthodique guidée :**

1. Énoncer la règle ou la définition appropriée.

2. Développer l'argumentation en citant des exemples précis tirés du cours.

3. Conclure de manière claire et synthétique.



## 6. Pièges fréquents & Erreurs à éviter aux examens officiels

- ⚠️ **Confusion terminologique** : Ne pas confondre les termes voisins mais distincts.

- ⚠️ **Oubli des justifications** : Toute affirmation à l'examen doit être étayée par une définition ou une loi du cours.

- ⚠️ **Réponses imprécises** : Utiliser toujours le vocabulaire canonique du programme officiel.



## 7. Synthèse essentielle

À retenir impérativement :

- Maîtriser les définitions fondamentales de **$cleanTopic**.

- Savoir mobiliser les exemples types présentés dans ce cours.

- Relire attentivement la fiche de synthèse avant toute épreuve officielle.

''';
    } else {
      return '''

# OFFICIAL LESSON: $cleanTopic

**Subject:** $cleanSubject | **Framework:** Cameroon Official Syllabus (MINESEC / GCE Board, Week $weekNumber)



## 1. Introduction & Lesson Objectives

This official lesson note is aligned with the approved Cameroon Secondary Curriculum (MINESEC / GCE Board).

Key student learning outcomes:

- Understand and define the essential principles governing **$cleanTopic**.

- Master the technical vocabulary, laws, and mechanisms underlying this syllabus area.

- Confidently apply these principles in examination-type problems and real-life scenarios.



## 2. Comprehensive Terminology & Core Definitions

- **$cleanTopic**: Central curriculum subject matter encompassing the specific principles and methods studied in this unit.

- **Operational Scope**: The precise academic context and observational criteria required for testing.

${subtopics != null && subtopics.isNotEmpty ? '- **Syllabus Sub-topics** : $subtopics\n' : ''}

## 3. Theoretical Framework, Laws, Rules & Formulas

Mastery of this topic requires memorizing and applying the following core rules:

1. **Core Principle**: All scientific and academic deduction relies upon rigorous observation and rule application.

2. **Analysis Method**: Identify relevant variables, apply the governing relationship, and verify consistency.

3. **Formal Notation**: Use standard units, symbols, and terminology required by official examiners.



## 4. In-Depth Step-by-Step Lesson Development

### A. Fundamentals and Core Framework

In-depth study of **$cleanTopic** highlights the essential relationships necessary for thorough mastery of the syllabus.



### B. Detailed Mechanisms and Systematic Operations

Breakdown into three clear operational stages:

- Stage 1: Data gathering and rule identification.

- Stage 2: Systematic analysis and deduction.

- Stage 3: Verification, error-checking, and mastery confirmation.



## 5. Step-by-Step Worked Applications & Model Problem Solutions

**Typical Examination Question:**

Explain how to apply the principles of **$cleanTopic** in a standard examination problem.

**Step-by-Step Worked Solution:**

1. State the relevant definition or governing theorem.

2. Formulate the solution citing concrete syllabus examples.

3. Conclude with a clear, unambiguous answer.



## 6. Common Examination Pitfalls & Mistakes to Avoid

- ⚠️ **Term Confusion**: Never interchange related but distinct technical terms.

- ⚠️ **Missing Justifications**: Always quote the relevant principle or formula.

- ⚠️ **Vague Answers**: Always employ official syllabus terminology.



## 7. Key Takeaways Summary

Must-memorize revision points:

- Review the core definitions of **$cleanTopic**.

- Rehearse the standard worked examples.

- Read through this summary sheet before official assessments.

''';
    }
  }

  String _lastModel = SupabaseCloudService.geminiModel;

  Future<Map<String, String>> _ctx(AppUser? u) async {
    if (u == null) return {};

    final cached = _ctxCache[u.id];

    if (cached != null) return cached;

    final out = <String, String>{'name': u.fullName};

    try {
      final p = await _list('/student_profiles', {
        'user_id': 'eq.${u.id}',
        'select': '*',
      });

      if (p.isNotEmpty) {
        final m = p.first as Map<String, dynamic>;

        final cid = (m['class_id'] as num?)?.toInt();

        if (cid != null) {
          final c = await _list('/classes', {
            'id': 'eq.$cid',
            'select': 'name',
          });

          if (c.isNotEmpty) out['class'] = c.first['name'] as String;
        }

        out['age'] = '${m['age'] ?? ''}';

        out['hobbies'] = '${m['hobbies_json'] ?? ''}';

        out['style'] = '${m['learning_style'] ?? ''}';

        out['difficult'] = '${m['difficult_subjects_json'] ?? ''}';

        out['goal'] = '${m['academic_goal'] ?? ''}';
      }
    } catch (_) {}

    _ctxCache[u.id] = out;

    return out;
  }

  String _system(Map<String, String> c, String lang, {bool hasHistory = false}) {
    final fr = lang == 'fr';
    final name = (c['name'] ?? '').trim().split(' ').first;
    final displayName = name.isNotEmpty ? name : (fr ? "l'élève" : 'Student');

    final strictLanguageRule = fr
        ? '''RÈGLE ABSOLUE ET INVIOLABLE DE LANGUE :
L'interface de l'application et l'élève sont en FRANÇAIS (FR).
TOUT CE QUE TU ÉCRIS (explications, étapes de calcul, formules, démonstrations, définitions, simulations, résumés et conclusions) DOIT ÊTRE RÉDIGÉ STRICTEMENT ET ENTIÈREMENT EN FRANÇAIS.
Même si la question de l'élève est posée en anglais ou si une photo d'exercice/examen en anglais est fournie, traduis et explique tout rigoureusement en français pur. Ne mélange JAMAIS les langues.'''
        : '''STRICT AND INVIOLABLE LANGUAGE RULE:
The application interface and student are in ENGLISH (EN).
ALL of your output (explanations, calculation steps, formulas, proofs, definitions, simulations, summaries, and conclusions) MUST BE WRITTEN STRICTLY AND ENTIRELY IN ENGLISH.
Even if the student's question is in French or a French document is provided, translate and explain everything strictly in English. Never mix languages.''';

    if (hasHistory) {
      return fr
          ? '''Tu es Kivora AI, un enseignant expert et précis du programme officiel camerounais (MINESEC / GCE Board).
$strictLanguageRule
RÈGLE DE CONTINUITÉ : Tu es dans un dialogue pédagogique continu avec l'élève $displayName.
NE SALUE PAS l'élève. Ne dis JAMAIS "Bonjour" ni "Comment puis-je t'aider".
Réponds directement, rigoureusement et clairement à la relance de l'élève en lien direct avec la question et la solution précédente.'''
          : '''You are Kivora AI, an expert and concise teacher aligned strictly with the Cameroon official syllabus (MINESEC / Cameroon GCE Board).
$strictLanguageRule
CONTINUITY RULE: You are engaged in an ongoing teaching dialogue with student $displayName.
DO NOT greet the student. NEVER say "Hello" or "How can I help you".
Directly, rigorously, and clearly address the student's follow-up question in the direct context of the previous steps and solution.''';
    }

    return fr
        ? '''Tu es Kivora AI, un enseignant expert et précis du programme officiel camerounais (MINESEC / GCE Board).
$strictLanguageRule
RÈGLE PRIMORDIALE : Sois concis, direct, pédagogique et rigoureux.
Ne salue pas l'élève avec des formules répétitives.
Ne raconte JAMAIS d'histoires sur Douala, Yaoundé, la météo, le football ou tes sentiments, sauf si l'élève pose expressément une question dessus.
Fournis une explication claire, académique, rigoureuse et bien structurée étape par étape.'''
        : '''You are Kivora AI, an expert and concise teacher aligned strictly with the Cameroon official syllabus (MINESEC / Cameroon GCE Board).
$strictLanguageRule
CARDINAL RULE: Be concise, direct, pedagogical, and rigorous.
Do not repeat empty greetings.
Never ramble about football, cities, weather, or personal chatter unless explicitly asked.
Provide a clear, academic, rigorous, and well-structured step-by-step explanation.''';
  }

  Future<Map<String, dynamic>?> _topic(int? progressionId) async {
    if (progressionId == null) return null;

    try {
      final r = await _list('/official_progressions', {
        'id': 'eq.$progressionId',
        'select': 'subject_name,topic_title,subtopics',
      });

      return r.isEmpty ? null : r.first as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _topicLine(
    Map<String, dynamic>? t,
    String? subject,
    String? title,
    String lang,
  ) {
    final s = (t?['subject_name'] ?? subject ?? '').toString();

    final ti = (t?['topic_title'] ?? title ?? '').toString();

    final st = (t?['subtopics'] ?? '').toString();

    if (s.isEmpty && ti.isEmpty) return '';

    final b = StringBuffer(
      lang == 'fr' ? 'Chapitre en cours : ' : 'Current topic: ',
    );

    b.write('$s — $ti');

    if (st.isNotEmpty) b.write(' ($st)');

    return b.toString();
  }

  Future<void> _save(
    AppUser? u,
    int? progId,
    String type,
    String prompt,
    String response,
  ) async {
    if (u == null) return;

    try {
      await http.post(
        _u('/ai_interactions'),

        headers: {..._h, 'Prefer': 'return=minimal'},

        body: jsonEncode({
          'user_id': u.id,

          'progression_id': progId,

          'interaction_type': type,

          'prompt': prompt,

          'response': response,
        }),
      );
    } catch (_) {}
  }

  SimulationData buildSimulation(String topic, String subject, bool fr) {
    final cleanTopic = topic.isNotEmpty ? topic : (fr ? 'Leçon' : 'Lesson');
    final cleanSubject = subject.isNotEmpty
        ? cleanSubjectName(subject)
        : (fr ? 'Matière' : 'Subject');

    final subjLower = cleanSubject.toLowerCase();
    final topicLower = cleanTopic.toLowerCase();

    final isFashionOrArt = subjLower.contains('fashion') ||
        subjLower.contains('artisanat') ||
        subjLower.contains('art') ||
        subjLower.contains('dessin') ||
        subjLower.contains('figurine') ||
        subjLower.contains('couture') ||
        topicLower.contains('figurine') ||
        topicLower.contains('drawing') ||
        topicLower.contains('portrait');

    final isAgriOrBreeding = subjLower.contains('elevage') ||
        subjLower.contains('élevage') ||
        subjLower.contains('porc') ||
        subjLower.contains('animale') ||
        subjLower.contains('vegetale') ||
        subjLower.contains('végétale') ||
        subjLower.contains('agri') ||
        subjLower.contains('travail manuel (production') ||
        topicLower.contains('porc') ||
        topicLower.contains('elevage') ||
        topicLower.contains('élevage') ||
        topicLower.contains('culture');

    final isBusinessOrAdmin = subjLower.contains('business') ||
        subjLower.contains('management') ||
        subjLower.contains('gestion') ||
        subjLower.contains('comptab') ||
        subjLower.contains('account') ||
        subjLower.contains('commerce') ||
        subjLower.contains('stenotyp') ||
        subjLower.contains('sténotyp') ||
        topicLower.contains('management') ||
        topicLower.contains('material');

    final isUrbanOrGeo = subjLower.contains('géo') ||
        subjLower.contains('geog') ||
        topicLower.contains('urban') ||
        topicLower.contains('settlement') ||
        topicLower.contains('ville') ||
        topicLower.contains('population') ||
        topicLower.contains('climat') ||
        topicLower.contains('hinterland') ||
        topicLower.contains('rural') ||
        topicLower.contains('carto');

    final isHistory = subjLower.contains('hist') ||
        topicLower.contains('guerre') ||
        topicLower.contains('war') ||
        topicLower.contains('wwii') ||
        topicLower.contains('ww2') ||
        topicLower.contains('traité') ||
        topicLower.contains('treaty') ||
        topicLower.contains('cameroun') ||
        topicLower.contains('colonial') ||
        topicLower.contains('revolution') ||
        topicLower.contains('decoloniz') ||
        topicLower.contains('décolonis');

    final isLang = subjLower.contains('anglais') ||
        subjLower.contains('english') ||
        subjLower.contains('français') ||
        subjLower.contains('francais') ||
        subjLower.contains('french') ||
        subjLower.contains('littérature') ||
        subjLower.contains('literature') ||
        subjLower.contains('langue') ||
        topicLower.contains('dialogue') ||
        topicLower.contains('communication') ||
        topicLower.contains('speaking');

    final isSci = subjLower.contains('physiq') ||
        subjLower.contains('chimie') ||
        subjLower.contains('chem') ||
        subjLower.contains('biol') ||
        subjLower.contains('svt') ||
        subjLower.contains('scien') ||
        subjLower.contains('radioact') ||
        topicLower.contains('radioact');

    final isMath = subjLower.contains('math') ||
        subjLower.contains('calcul') ||
        topicLower.contains('factor') ||
        topicLower.contains('polynomial') ||
        topicLower.contains('equation');

    if (isFashionOrArt) {
      return SimulationData(
        title: fr ? 'Atelier Dessin & Mode : $cleanTopic' : 'Fashion Studio Lab: $cleanTopic',
        scenario: fr
            ? 'Atelier pratique de dessin de mode : application du canon anatomique et maîtrise du tracé pour "$cleanTopic".'
            : 'Interactive design studio: applying anatomical proportions and line mastery for "$cleanTopic".',
        keyTakeaway: fr
            ? 'La construction rigoureuse du canon de proportion assure un rendu professionnel et conforme aux critères d\'examen.'
            : 'Proportion grid construction guarantees accurate anatomical alignment required in official exams.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Grille des proportions & Axe d\'équilibre' : 'Step 1: Proportion Grid & Balance Axis',
            action: fr
                ? 'Tracer l\'axe vertical central et repérer les 8 modules de tête pour caler la posture de "$cleanTopic".'
                : 'Draw the vertical plumb line and demarcate the 8 head units to position the stance of "$cleanTopic".',
            outcome: fr
                ? 'L\'équilibre postural et les repères osseux (épaules, bassin) sont parfaitement étalonnés.'
                : 'Postural balance and landmarks (shoulders, pelvis) are correctly established.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Esquisse des masses & Ligne de contour' : 'Step 2: Mass Outline & Contour Shaping',
            action: fr
                ? 'Dessiner les volumes musculaires et les courbures spécifiques du profil/face selon les règles de $cleanTopic.'
                : 'Draft anatomical masses and curvature lines reflecting the exact angles of $cleanTopic.',
            outcome: fr
                ? 'La silhouette prend forme avec des proportions fluides et réalistes.'
                : 'Silhouette takes clear visual shape with fluid, realistic proportions.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Finition technique & Critères d\'évaluation' : 'Step 3: Technical Inking & Exam Criteria',
            action: fr
                ? 'Nettoyer les lignes de construction, accentuer les arêtes principales et vérifier la conformité d\'examen.'
                : 'Clean construction guidelines, enhance primary contours, and check against official marking guides.',
            outcome: fr
                ? 'Planche technique finalisée avec précision, prête pour la note maximale !'
                : 'Technical fashion plate completed with precision, ready for top exam scores!',
          ),
        ],
      );
    }

    if (isAgriOrBreeding) {
      return SimulationData(
        title: fr ? 'Simulateur Agricole & Élevage : $cleanTopic' : 'Agricultural & Livestock Lab: $cleanTopic',
        scenario: fr
            ? 'Mise en situation d\'exploitation agropastorale : planification technique et conduite d\'élevage pour "$cleanTopic".'
            : 'Agro-pastoral farm simulation: operational planning and livestock management for "$cleanTopic".',
        keyTakeaway: fr
            ? 'Le respect des normes sanitaires, du rationnement et du logement garantit un rendement optimal et durable.'
            : 'Adherence to sanitation, balanced feeding, and biosecurity ensures peak agricultural productivity.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Choix du site & Infrastructure' : 'Step 1: Site Selection & Shelter Design',
            action: fr
                ? 'Évaluer la topographie, la ventilation et installer l\'enclos/parcelle selon les règles de "$cleanTopic".'
                : 'Assess terrain topography, air flow, and set up housing/beds according to "$cleanTopic" rules.',
            outcome: fr
                ? 'Conditions de biosécurité et de bien-être sanitaire optimales établies.'
                : 'Biosecurity boundaries and sanitary baseline successfully established.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Conduite technique & Rationnement' : 'Step 2: Technical Protocol & Nutrition Plan',
            action: fr
                ? 'Calculer la ration alimentaire équilibrée (énergie, protéines, minéraux) et administrer les soins préventifs.'
                : 'Formulate balanced nutritional feed rations (energy, protein, minerals) and administer prophylaxis.',
            outcome: fr
                ? 'Croissance régulière observée sans carence ni risque épidémique.'
                : 'Steady growth verified with zero nutritional deficiency or pest outbreak.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Bilan zootechnique & Normes officielles' : 'Step 3: Farm Ledger & Technical Audit',
            action: fr
                ? 'Consigner les indices de consommation, les gains de poids et vérifier la rentabilité de la production.'
                : 'Log feed conversion ratios, weight gains, and verify commercial viability for exam questions.',
            outcome: fr
                ? 'Maîtrise totale des fiches techniques et des calculs d\'examen validée !'
                : 'Full mastery of practical farm metrics and exam calculation steps confirmed!',
          ),
        ],
      );
    }

    if (isBusinessOrAdmin) {
      return SimulationData(
        title: fr ? 'Simulateur Entreprise & Gestion : $cleanTopic' : 'Business Management Simulator: $cleanTopic',
        scenario: fr
            ? 'Simulation en entreprise réelle : gestion opérationnelle, flux de documents et prise de décision pour "$cleanTopic".'
            : 'Corporate operational simulation: managing material workflows, documentation, and records for "$cleanTopic".',
        keyTakeaway: fr
            ? 'L\'organisation rigoureuse des stocks et des flux garantit la pérennité financière et l\'efficacité de l\'organisation.'
            : 'Rigorous inventory and ledger tracking ensures organizational control and financial compliance.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Réception des flux & Codification' : 'Step 1: Input Flow & Document Codification',
            action: fr
                ? 'Enregistrer les entrées, vérifier les bons de commande/livraison et codifier selon les règles de "$cleanTopic".'
                : 'Inspect incoming assets/invoices, check delivery vouchers, and classify under "$cleanTopic" rules.',
            outcome: fr
                ? 'Traçabilité complète des éléments établie dans le registre officiel.'
                : 'Full transaction traceability recorded in the official inventory register.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Traitement comptable & Gestion des matières' : 'Step 2: Processing & Allocation Operations',
            action: fr
                ? 'Appliquer la méthode de valorisation (FIFO, CUMP) ou rédiger les synthèses administratives correspondantes.'
                : 'Apply valuation models (FIFO, weighted average) and allocate resources to designated departments.',
            outcome: fr
                ? 'Équilibre des comptes et suivi des consommations sans écart d\'inventaire.'
                : 'Account reconciliation completed with zero discrepancy.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Contrôle de gestion & Synthèse d\'examen' : 'Step 3: Audit Report & Exam Framework',
            action: fr
                ? 'Établir l\'état récapitulatif, interpréter les écarts et formuler les recommandations stratégiques.'
                : 'Generate final audit summary, analyze variances, and draft formal exam responses.',
            outcome: fr
                ? 'Dossier professionnel conforme aux attentes des jurys d\'examen !'
                : 'Management dossier finalized according to national examination standards!',
          ),
        ],
      );
    }

    if (isUrbanOrGeo) {
      return SimulationData(
        title: fr ? 'Simulateur Géographie Urbaine & Territoires : $cleanTopic' : 'Urban Geography & Settlement Lab: $cleanTopic',
        scenario: fr
            ? 'Modélisation spatiale interactive : analyse des zones concentriques, des flux de population et des relations ville-campagne pour "$cleanTopic".'
            : 'Interactive spatial modeling: analyzing concentric rings, population flows, and urban-rural linkages for "$cleanTopic".',
        keyTakeaway: fr
            ? 'L\'organisation spatiale (CBD, banlieues, hinterland) régit les flux démographiques et les dynamiques de peuplement.'
            : 'Concentric zoning (CBD, residential suburbs, rural hinterland) dictates commuter flows and regional development.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Délimitation du CBD & Noyau Urbain' : 'Step 1: CBD Demarcation & Urban Core',
            action: fr
                ? 'Repérer le centre des affaires (haute densité, services tertiaires) et son aire d\'attraction pour "$cleanTopic".'
                : 'Identify the central business district (high density, tertiary sector) and its sphere of influence for "$cleanTopic".',
            outcome: fr
                ? 'Le noyau urbain et la concentration des fonctions tertiaires sont établis.'
                : 'Urban core and high-density commercial node firmly identified.',
            scene: SimulationScene(
              environment: 'city',
              objects: [
                SceneObject(sprite: 'city', label: 'CBD Core', x: 0.50, y: 0.44, color: 'blue', scale: 1.3),
                SceneObject(sprite: 'car', label: 'Commuter Flow', x: 0.22, y: 0.54, color: 'cyan'),
                SceneObject(sprite: 'tree', label: 'Hinterland', x: 0.82, y: 0.52, color: 'green'),
              ],
              motions: [
                SceneMotion(fromX: 0.24, fromY: 0.54, toX: 0.46, toY: 0.46, particle: 'spark', color: 'cyan', label: 'Pendulaire'),
                SceneMotion(fromX: 0.78, fromY: 0.52, toX: 0.54, toY: 0.46, particle: 'photon', color: 'green', label: 'Vivres'),
              ],
            ),
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Couronnes résidentielles & Banlieues' : 'Step 2: Residential Belts & Suburban Rings',
            action: fr
                ? 'Cartographier les zones d\'habitat continu, l\'étalement urbain et les axes autoroutiers de transport.'
                : 'Map concentric residential belts, suburban sprawl, and primary arterial transit corridors.',
            outcome: fr
                ? 'Gradation nette de la densité du centre vers la périphérie observée.'
                : 'Clear outward density gradient from core to periphery mapped.',
            scene: SimulationScene(
              environment: 'city',
              objects: [
                SceneObject(sprite: 'city', label: 'CBD Central', x: 0.50, y: 0.44, color: 'blue', scale: 1.3),
                SceneObject(sprite: 'building', label: 'Banlieues', x: 0.24, y: 0.52, color: 'blue'),
                SceneObject(sprite: 'tree', label: 'Rural Supply', x: 0.80, y: 0.52, color: 'green'),
              ],
              motions: [
                SceneMotion(fromX: 0.28, fromY: 0.52, toX: 0.46, toY: 0.46, particle: 'spark', color: 'cyan', label: 'Migration'),
              ],
            ),
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Relations Ville-Campagne & Croquis d\'examen' : 'Step 3: Rural-Urban Linkage & Exam Model',
            action: fr
                ? 'Analyser les flux d\'approvisionnement vivrier et formaliser le croquis de synthèse géographique.'
                : 'Analyze rural hinterland food supplies and finalize the official exam synthesis sketch.',
            outcome: fr
                ? 'Maîtrise complète du croquis et de l\'explication géographique validée !'
                : 'Full mastery of spatial sketches and geographic exam questions verified!',
            scene: SimulationScene(
              environment: 'city',
              objects: [
                SceneObject(sprite: 'city', label: 'Pôle Urbain', x: 0.50, y: 0.44, color: 'blue', scale: 1.3),
                SceneObject(sprite: 'star', label: 'Croquis d\'Examen', x: 0.82, y: 0.50, color: 'amber'),
              ],
              motions: [
                SceneMotion(fromX: 0.54, fromY: 0.44, toX: 0.78, toY: 0.50, particle: 'spark', color: 'amber', label: 'Synthèse'),
              ],
            ),
          ),
        ],
      );
    }

    if (isHistory) {
      return SimulationData(
        title: fr ? 'Simulation Historique & Géopolitique : $cleanTopic' : 'Historical & Geopolitical Lab: $cleanTopic',
        scenario: fr
            ? 'Reconstitution interactive en salle de crise : analyse documentaire, lignes de front et traités diplomatiques de "$cleanTopic".'
            : 'Interactive war-room & diplomacy reconstruction: analyzing battlefronts, treaties, and turning points for "$cleanTopic".',
        keyTakeaway: fr
            ? 'La contextualisation critique des alliances, des batailles et des traités permet de maîtriser l\'épreuve d\'histoire.'
            : 'Critical analysis of alliances, battlefront dynamics, and peace treaties unlocks top exam performance.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Analyse des blocs d\'alliances & Causes' : 'Step 1: Alliance Blocs & Strategic Context',
            action: fr
                ? 'Identifier les coalitions belligérantes (Alliés contre Axe / blocs) et les traités fondateurs pour "$cleanTopic".'
                : 'Identify belligerent coalitions (Allied vs Axis powers) and underlying causes for "$cleanTopic".',
            outcome: fr
                ? 'Cadre géopolitique et rapports de force fermement établis sans anachronisme.'
                : 'Geopolitical boundaries and alliance commitments clearly established.',
            scene: SimulationScene(
              environment: 'history',
              objects: [
                SceneObject(sprite: 'shield', label: 'Alliés / Allies', x: 0.22, y: 0.48, color: 'blue', scale: 1.2),
                SceneObject(sprite: 'flag', label: 'Ligne de Front', x: 0.50, y: 0.48, color: 'amber', scale: 1.2),
                SceneObject(sprite: 'shield', label: 'Axe / Axis', x: 0.78, y: 0.48, color: 'red', scale: 1.2),
              ],
              motions: [
                SceneMotion(fromX: 0.26, fromY: 0.48, toX: 0.46, toY: 0.48, particle: 'spark', color: 'cyan', label: 'Offensive'),
                SceneMotion(fromX: 0.74, fromY: 0.48, toX: 0.54, toY: 0.48, particle: 'spark', color: 'red', label: 'Assaut'),
              ],
            ),
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Tournants décisifs & Opérations de front' : 'Step 2: Turning Points & Frontline Operations',
            action: fr
                ? 'Suivre les batailles décisives (Stalingrad, Midway, Normandie) et les contre-offensives sur la ligne de front.'
                : 'Track decisive turning points, counter-offensives, and breakthrough operations.',
            outcome: fr
                ? 'Les phases du conflit et le basculement militaire sont clairement articulés.'
                : 'War phases and military turning points logically categorized.',
            scene: SimulationScene(
              environment: 'history',
              objects: [
                SceneObject(sprite: 'shield', label: 'Grand Alliance', x: 0.22, y: 0.48, color: 'blue', scale: 1.2),
                SceneObject(sprite: 'flag', label: 'Tournant Clé', x: 0.50, y: 0.48, color: 'amber', scale: 1.3),
                SceneObject(sprite: 'shield', label: 'Axe en Recul', x: 0.78, y: 0.48, color: 'red', scale: 1.1),
              ],
              motions: [
                SceneMotion(fromX: 0.28, fromY: 0.48, toX: 0.48, toY: 0.48, particle: 'photon', color: 'cyan', label: 'Percée'),
              ],
            ),
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Conférences de Paix & Traités internationaux' : 'Step 3: Peace Settlements & Post-War Order',
            action: fr
                ? 'Synthétiser les accords de paix (Yalta, Potsdam, Charte de l\'ONU) et bâtir la conclusion de dissertation.'
                : 'Synthesize peace treaties (Yalta, UN charter, reparations) and formulate the exam essay response.',
            outcome: fr
                ? 'Maîtrise totale des dates repères, causes et conséquences validée pour l\'examen !'
                : 'Full mastery of key dates, treaties, and exam thesis confirmed!',
            scene: SimulationScene(
              environment: 'history',
              objects: [
                SceneObject(sprite: 'document', label: 'Traités de Paix', x: 0.50, y: 0.48, color: 'amber', scale: 1.25),
                SceneObject(sprite: 'star', label: 'Nouvel Ordre Mondial', x: 0.80, y: 0.48, color: 'green'),
              ],
              motions: [
                SceneMotion(fromX: 0.54, fromY: 0.48, toX: 0.76, toY: 0.48, particle: 'spark', color: 'green', label: 'ONU / Paix'),
              ],
            ),
          ),
        ],
      );
    }

    if (isLang) {
      return SimulationData(
        title: fr ? 'Simulation Dialogue : $cleanTopic' : 'Interactive Dialogue: $cleanTopic',
        scenario: fr
            ? 'Deux élèves (Paul et Sophie) engagent une conversation en classe pour mettre en pratique "$cleanTopic" dans un dialogue réel.'
            : 'Two students (John and Mary) engage in a live classroom conversation putting "$cleanTopic" into practical use.',
        keyTakeaway: fr
            ? 'La communication orale et écrite sur "$cleanTopic" est maîtrisée avec fluidité et précision grammaticale.'
            : 'Verbal communication and expression on "$cleanTopic" mastered with natural fluency and grammar precision.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Amorcer la communication' : 'Step 1: Context & Opening Exchange',
            action: fr
                ? 'Paul pose une question à Sophie en utilisant la structure linguistique clé de "$cleanTopic".'
                : 'John initiates the dialogue with Mary using the key grammar and phrasing pattern of "$cleanTopic".',
            outcome: fr
                ? 'Sophie comprend le message et identifie le registre d\'expression approprié.'
                : 'Mary understands the prompt and identifies the correct conversational register.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Échange dynamique & Interaction' : 'Step 2: Dynamic Response & Fluency',
            action: fr
                ? 'Sophie développe sa réponse avec des tournures variées. Paul ajuste son intonation et répond du tac au tac.'
                : 'Mary responds using rich vocabulary, and John answers promptly demonstrating correct tense and syntax.',
            outcome: fr
                ? 'L\'échange démontre l\'usage naturel et sans faute des expressions au programme.'
                : 'The exchange demonstrates error-free, natural usage of syllabus expressions.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Synthèse & Critères d\'évaluation' : 'Step 3: Synthesis & Exam Criteria',
            action: fr
                ? 'Les deux élèves relèvent les tournures types et les pièges d\'examen à éviter lors de l\'épreuve.'
                : 'Both students highlight target phrases and common mistakes to avoid in Cameroon GCE exams.',
            outcome: fr
                ? 'Compétences communicatives pour "$cleanTopic" validées avec succès !'
                : 'Communication competencies for "$cleanTopic" successfully validated!',
          ),
        ],
      );
    }

    if (isSci) {
      return SimulationData(
        title: fr ? 'Simulation Laboratoire : $cleanTopic' : 'Virtual Science Lab: $cleanTopic',
        scenario: fr
            ? 'Expérimentation guidée au laboratoire pour observer directement les réactions et lois physiques de "$cleanTopic" ($cleanSubject).'
            : 'Virtual laboratory walkthrough observing kinetic reactions and scientific laws of "$cleanTopic" ($cleanSubject).',
        keyTakeaway: fr
            ? 'L\'observation expérimentale confirme la relation de cause à effet et les lois officielles du programme.'
            : 'Experimental observation confirms the theoretical laws and principles governing $cleanTopic.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Dispositif expérimental & Conditions' : 'Step 1: Experimental Setup & Parameters',
            action: fr
                ? 'Mise en place des instruments, réactifs ou grandeurs physiques initiales pour "$cleanTopic".'
                : 'Calibrate instruments, reagents, or physical parameters for "$cleanTopic".',
            outcome: fr
                ? 'Conditions initiales étalonnées et prêtes pour la mesure dynamique.'
                : 'Stable baseline established and ready for measurement.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Déclenchement & Observation active' : 'Step 2: Reaction Trigger & Active Changes',
            action: fr
                ? 'Observation des variations dynamiques (température, désintégration, déplacement ou réaction).'
                : 'Observe active transformations (decay, field movement, or chemical changes) in real time.',
            outcome: fr
                ? 'Les grandeurs physiques suivent fidèlement les équations théoriques du cours.'
                : 'Physical quantities strictly follow the governing scientific formula.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Interprétation & Formule d\'examen' : 'Step 3: Law Synthesis & Exam Calculation',
            action: fr
                ? 'Formalisation de la relation mathématique et méthode de calcul type pour les examens officiels.'
                : 'Derive final mathematical relation and exam problem-solving procedure.',
            outcome: fr
                ? 'Maîtrise complète de l\'exercice type sur "$cleanTopic" confirmée !'
                : 'Full mastery of standard examination exercises on "$cleanTopic" confirmed!',
          ),
        ],
      );
    }

    if (isMath) {
      return SimulationData(
        title: fr ? 'Simulation Mathématique : $cleanTopic' : 'Mathematical Solver: $cleanTopic',
        scenario: fr
            ? 'Visualiseur algorithmique et algébrique pas-à-pas pour décomposer et résoudre les exercices sur "$cleanTopic".'
            : 'Step-by-step algebraic and graphical visualizer resolving problem sets on "$cleanTopic".',
        keyTakeaway: fr
            ? 'L\'application rigoureuse des théorèmes mène à la solution exacte et élimine les erreurs de calcul.'
            : 'Rigorous theorem application produces exact solutions and eliminates arithmetic mistakes.',
        steps: [
          SimulationStep(
            stepNumber: 1,
            title: fr ? 'Étape 1 : Identification du théorème & Hypothèses' : 'Step 1: Theorem Identification & Setup',
            action: fr
                ? 'Poser les données, identifier les variables et énoncer la règle clé relative à "$cleanTopic".'
                : 'State given variables, identify target unknowns, and declare the core theorem for "$cleanTopic".',
            outcome: fr
                ? 'Équation initiale posée avec clarté sans ambiguïté.'
                : 'Initial equation structured cleanly without ambiguity.',
          ),
          SimulationStep(
            stepNumber: 2,
            title: fr ? 'Étape 2 : Résolution algébrique pas-à-pas' : 'Step 2: Step-by-Step Algebraic Operations',
            action: fr
                ? 'Développer, factoriser, substituer ou tracer la fonction selon les étapes méthodiques requises.'
                : 'Substitute, factor, expand, or plot according to formal examination methodology.',
            outcome: fr
                ? 'Chaque ligne de calcul découle logiquement de la précédente.'
                : 'Every line follows logically from the previous operation.',
          ),
          SimulationStep(
            stepNumber: 3,
            title: fr ? 'Étape 3 : Vérification du résultat & Choix de la réponse' : 'Step 3: Verification & Correct Option',
            action: fr
                ? 'Vérifier la cohérence de la racine ou de la valeur obtenue et conclure avec la bonne option.'
                : 'Plug the solution back into the original equation to verify consistency and identify the correct option.',
            outcome: fr
                ? 'Résultat rigoureusement exact et prêt pour l\'examen !'
                : 'Result fully verified and ready for exam success!',
          ),
        ],
      );
    }

    return SimulationData(
      title: fr
          ? 'Simulation Vidéo : $cleanTopic'
          : 'Video Simulation: $cleanTopic',

      scenario: fr
          ? 'Expérimentation animée et démonstration guidée pas-à-pas pour observer directement le mécanisme de $cleanTopic ($cleanSubject).'
          : 'Animated video walkthrough exploring the core mechanisms of $cleanTopic ($cleanSubject).',

      keyTakeaway: fr
          ? 'L\'observation dynamique confirme l\'application concrète des lois et principes de $cleanTopic.'
          : 'Dynamic visual simulation confirms the real-world application of $cleanTopic principles.',

      steps: [
        SimulationStep(
          stepNumber: 1,

          title: fr
              ? 'Étape 1 : Paramètres initiaux & Hypothèse'
              : 'Step 1: Baseline Setup & Parameters',

          action: fr
              ? 'Mise en place des variables de départ selon les règles officielles de $cleanTopic.'
              : 'Configure starting baseline variables for $cleanTopic.',

          outcome: fr
              ? 'L\'état de référence est établi et prêt pour l\'analyse visuelle.'
              : 'Initial stable state established and ready for dynamic testing.',
        ),

        SimulationStep(
          stepNumber: 2,

          title: fr
              ? 'Étape 2 : Interaction & Observation dynamique'
              : 'Step 2: Dynamic Process & Interaction',

          action: fr
              ? 'Application des principes du cours : observation des transformations et réactions concrètes.'
              : 'Apply lesson principles: trigger active transformations and observe responses.',

          outcome: fr
              ? 'La formule et le principe s\'illustrent par des variations visibles et mesurables.'
              : 'The governing formula displays visible, measurable variations in real time.',
        ),

        SimulationStep(
          stepNumber: 3,

          title: fr
              ? 'Étape 3 : Conclusion & Règle d\'examen'
              : 'Step 3: Synthesis & Exam Rule',

          action: fr
              ? 'Interprétation des résultats et formalisation de la règle à retenir pour les examens (GCE / BEPC / Probatoire).'
              : 'Consolidate takeaways and apply standard exam problem-solving rules.',

          outcome: fr
              ? 'Maîtrise complète du concept de $cleanTopic validée !'
              : 'Concept mastery for $cleanTopic confirmed!',
        ),
      ],
    );
  }

  Future<AiResponse> askTutor({
    required AppUser? user,

    required String question,

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    String languageCode = 'en',
    List<Map<String, String>>? conversationHistory,
  }) async {
    final c = await _ctx(user);

    final fr = languageCode == 'fr';

    final name = (c['name'] ?? '').trim().split(' ').first;

    final displayName = name.isNotEmpty ? name : (fr ? "l'élève" : "Student");

    final hasHistory = conversationHistory != null && conversationHistory.isNotEmpty;

    // Fast instant greeting response (<10ms) ONLY if there is no conversation history
    final qClean = question.trim().toLowerCase();

    final isGreeting = RegExp(
      r'^(hello|hi|hey|bonjour|salut|coucou|good morning|bonsoir)[\s!.]*$',
      caseSensitive: false,
    ).hasMatch(qClean);

    if (!hasHistory && isGreeting) {
      final reply = fr
          ? 'Bonjour $displayName ! Comment puis-je t\'aider aujourd\'hui ?'
          : 'Hello $displayName! How can I help you today?';

      await _save(user, progressionId, 'chat', question, reply);

      return AiResponse(
        interactionType: 'chat',
        content: reply,
        modelUsed: 'kivora-fast',
      );
    }

    final t = await _topic(progressionId);

    final tl = _topicLine(t, subjectName, topicTitle, languageCode);

    final topic = topicTitle ?? (t?['topic_title'] as String?) ?? '';

    final subject = subjectName ?? (t?['subject_name'] as String?) ?? '';

    String text;

    final langPromptHeader = fr
        ? '[LANGUE OBLIGATOIRE : FRANÇAIS - Réponds strictement et exclusivement en français. Il est strictement interdit d\'écrire en anglais même si l\'historique précédent ou la question est en anglais.]\n\n'
        : '[MANDATORY LANGUAGE: ENGLISH - Reply strictly and exclusively in English. It is strictly forbidden to write in French even if previous conversation history was in French.]\n\n';

    try {
      List<Map<String, dynamic>>? contentsList;
      if (hasHistory) {
        contentsList = [];
        for (final msg in conversationHistory) {
          final r = msg['role'] == 'user' ? 'user' : 'model';
          final txt = (msg['content'] ?? '').trim();
          if (txt.isNotEmpty) {
            contentsList.add({
              'role': r,
              'parts': [{'text': txt}],
            });
          }
        }
        contentsList.add({
          'role': 'user',
          'parts': [
            {
              'text':
                  '$langPromptHeader${tl.isEmpty ? '' : '$tl\n\n'}${languageCode == 'fr' ? 'Question de l\'élève' : 'Student question'}:\n$question',
            }
          ],
        });
      }

      text = await _gemini([
        {
          'text':
              '$langPromptHeader${tl.isEmpty ? '' : '$tl\n\n'}${languageCode == 'fr' ? 'Question de l\'élève' : 'Student question'}:\n$question',
        },
      ], system: _system(c, languageCode, hasHistory: hasHistory), fullContents: contentsList);
    } catch (_) {
      text = _buildAcademicAnswer(
        question: question,

        topicTitle: topic.isNotEmpty ? topic : null,

        subjectName: subject.isNotEmpty ? subject : null,

        isFr: fr,

        studentName: displayName,
      );
    }

    text = cleanMathNotation(text, displayName, fr);

    final qLower = question.toLowerCase();

    final wantsSimOrVideo =
        qLower.contains('simul') ||
        qLower.contains('vid') ||
        qLower.contains('anim') ||
        qLower.contains('expéri') ||
        qLower.contains('experi') ||
        qLower.contains('montre') ||
        qLower.contains('show') ||
        qLower.contains('visual') ||
        qLower.contains('cours') ||
        qLower.contains('expliq');

    SimulationData? sim;

    if (wantsSimOrVideo || topic.isNotEmpty) {
      sim = buildSimulation(topic, subject, fr);
    }

    if (wantsSimOrVideo && (topic.isNotEmpty || subject.isNotEmpty)) {
      final queryParam = Uri.encodeComponent(
        '${cleanSubjectName(subject)} $topic explication video cours',
      );

      final videoUrl =
          'https://www.youtube.com/results?search_query=$queryParam';

      final videoSection = fr
          ? '\n\n🎬 **Simulation vidéo recommandée :**\nRetrouvez des vidéos et démonstrations interactives : [Voir les vidéos explicatives]($videoUrl)\n*(Le lecteur de simulation animée Kivora est également disponible ci-dessus !)*'
          : '\n\n🎬 **Recommended Video Simulation:**\nExplore interactive demonstrations and step-by-step video explainers: [Watch Video Simulations]($videoUrl)\n*(The interactive Kivora video simulation player is also ready above!)*';

      text = '$text$videoSection';
    }

    await _save(user, progressionId, 'chat', question, text);

    return AiResponse(
      interactionType: 'chat',
      content: text,
      modelUsed: _lastModel,
      simulation: sim,
    );
  }

  static const Map<String, String> _mime = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',

    'gif': 'image/gif',
    'heic': 'image/heic',
    'pdf': 'application/pdf',

    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',

    'ogg': 'audio/ogg',
    'webm': 'audio/webm',
    'flac': 'audio/flac',
    'txt': 'text/plain',

    'mp4': 'video/mp4',
  };

  String _mimeOf(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    return _mime[ext] ?? 'application/octet-stream';
  }

  Future<AiResponse> askTutorMultimodal({
    required AppUser? user,

    required List<({String name, List<int> bytes})> mediaFiles,

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    String question = '',

    String languageCode = 'en',
    List<Map<String, String>>? conversationHistory,
  }) async {
    final c = await _ctx(user);

    final t = await _topic(progressionId);

    final tl = _topicLine(t, subjectName, topicTitle, languageCode);

    final fr = languageCode == 'fr';

    final q = question.trim().isEmpty
        ? (fr
              ? 'Explique-moi le contenu de ce document/cette image étape par étape.'
              : 'Explain the content of this file/image step by step.')
        : question.trim();

    final langPromptHeader = fr
        ? '[LANGUE OBLIGATOIRE : FRANÇAIS - Réponds strictement et exclusivement en français. Il est strictement interdit d\'écrire en anglais même si l\'historique précédent ou la question est en anglais.]\n\n'
        : '[MANDATORY LANGUAGE: ENGLISH - Reply strictly and exclusively in English. It is strictly forbidden to write in French even if previous conversation history was in French.]\n\n';

    final hasHistory = conversationHistory != null && conversationHistory.isNotEmpty;
    List<Map<String, dynamic>>? contentsList;
    if (hasHistory) {
      contentsList = [];
      for (final msg in conversationHistory) {
        final r = msg['role'] == 'user' ? 'user' : 'model';
        final txt = (msg['content'] ?? '').trim();
        if (txt.isNotEmpty) {
          contentsList.add({
            'role': r,
            'parts': [{'text': txt}],
          });
        }
      }
      contentsList.add({
        'role': 'user',
        'parts': [
          {'text': '$langPromptHeader${tl.isEmpty ? '' : '$tl\n\n'}$q'},
          for (final f in mediaFiles)
            {
              'inlineData': {
                'mimeType': _mimeOf(f.name),
                'data': base64.encode(f.bytes),
              },
            },
        ],
      });
    }

    final text = await _gemini([
      {'text': '$langPromptHeader${tl.isEmpty ? '' : '$tl\n\n'}$q'},

      for (final f in mediaFiles)
        {
          'inlineData': {
            'mimeType': _mimeOf(f.name),
            'data': base64.encode(f.bytes),
          },
        },
    ], system: _system(c, languageCode, hasHistory: hasHistory), fullContents: contentsList);

    await _save(
      user,
      progressionId,
      'chat',
      '[${mediaFiles.length} fichier(s)] $q',
      text,
    );

    return AiResponse(
      interactionType: 'chat',
      content: text,
      modelUsed: _lastModel,
    );
  }

  Future<AiResponse> summarizeTopic({
    required AppUser? user,

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    String languageCode = 'en',
  }) async {
    final c = await _ctx(user);

    final t = await _topic(progressionId);

    final tl = _topicLine(t, subjectName, topicTitle, languageCode);

    final fr = languageCode == 'fr';

    final cleanTopic =
        topicTitle ?? t?['topic_title'] ?? (fr ? 'Leçon' : 'Lesson');

    final cleanSubject =
        subjectName ?? t?['subject_name'] ?? (fr ? 'Matière' : 'Subject');

    final prompt = fr
        ? '''

$tl



Rédige un COURS MAGISTRAL COMPLET ET APPROFONDI (pas un simple résumé court) pour ce sujet officiel : "$cleanTopic" en "$cleanSubject".



Structure obligatoire du cours complet :

# COURS OFFICIEL : $cleanTopic

**Matière :** $cleanSubject | **Cadre :** Programme Officiel MINESEC Cameroun



## 1. Introduction & Objectifs de la leçon

(Compétences visées et cadre du curriculum officiel camerounais).



## 2. Définitions complètes & Vocabulaire clé

(Toutes les définitions académiques indispensables avec explications exhaustives).



## 3. Cadre théorique, Lois, Règles et Formules

(Présentation complète des principes, formules mathématiques/scientifiques ou règles juridiques/économiques avec leurs démonstrations et signification de chaque variable).



## 4. Développement approfondi du cours

(Explications détaillées de chaque aspect du chapitre, parties structurées A, B, C sans rien tronquer).



## 5. Applications concrètes & Exercices d'application résolus

(Exemples types d'examen résolus étape par étape avec la méthode détaillée).



## 6. Pièges fréquents & Erreurs à éviter aux examens officiels

(Conseils méthodologiques pour obtenir la note maximale aux examens).



## 7. Synthèse essentielle

(Les points fondamentaux à mémoriser pour l'épreuve).

'''
        : '''

$tl



Write a COMPREHENSIVE AND IN-DEPTH OFFICIAL LESSON NOTE (not a brief summary) for this syllabus topic: "$cleanTopic" in "$cleanSubject".



Mandatory complete structure:

# OFFICIAL LESSON: $cleanTopic

**Subject:** $cleanSubject | **Framework:** Cameroon Official Syllabus (MINESEC / GCE Board)



## 1. Introduction & Lesson Objectives

(Formal statement of core learning outcomes aligned with the official examination syllabus).



## 2. Comprehensive Terminology & Core Definitions

(Complete, detailed academic definitions of all technical terms).



## 3. Theoretical Framework, Laws, Rules & Formulas

(Exhaustive presentation of scientific/mathematical formulas, economic/legal rules, or governing principles with units and derivations).



## 4. In-Depth Step-by-Step Lesson Development

(Detailed, thorough academic breakdown divided into structured subsections A, B, C without leaving out any key concept).



## 5. Step-by-Step Worked Applications & Model Problem Solutions

(Typical exam-style questions with detailed, fully annotated step-by-step working and solutions).



## 6. Common Examination Pitfalls & Mistakes to Avoid (Cameroon GCE / Official Exams)

(Crucial examiner tips to secure maximum marks).



## 7. Key Takeaways Summary

(The master principles to memorize for test success).

''';

    String text;

    try {
      text = await _gemini([
        {'text': prompt},
      ], system: _system(c, languageCode));

      await _save(user, progressionId, 'summary', tl, text);
    } catch (_) {
      text = _buildFallbackComprehensiveCourse(
        cleanTopic: cleanTopic,

        cleanSubject: cleanSubject,

        subtopics: t?['subtopics']?.toString(),

        weekNumber: (t?['week_number'] as num?)?.toInt() ?? 1,

        isFr: fr,
      );
    }

    final sources = <Map<String, String>>[
      {
        'title': fr
            ? 'Épreuves & Corrigés GCE / MINESEC : $cleanTopic'
            : 'Cameroon GCE Past Questions & Answers: $cleanTopic',
        'url':
            'https://www.google.com/search?q=${Uri.encodeComponent('Cameroon GCE past questions answers $cleanSubject $cleanTopic')}',
      },
      {
        'title': fr
            ? 'Fiches de Cours & Révision Officielle MINESEC : $cleanTopic'
            : 'MINESEC Syllabus Guide & Revision Notes: $cleanTopic',
        'url':
            'https://www.google.com/search?q=${Uri.encodeComponent('MINESEC Cameroun cours fiche revision $cleanSubject $cleanTopic')}',
      },
      {
        'title': fr
            ? 'Exercices Résolus & Vidéos Démonstratives : $cleanTopic'
            : 'Solved Exam Problems & Video Walkthrough: $cleanTopic',
        'url':
            'https://www.youtube.com/results?search_query=${Uri.encodeComponent('$cleanSubject $cleanTopic cours exercice corrige')}',
      },
    ];

    final sim = buildSimulation(cleanTopic, cleanSubject, fr);

    return AiResponse(
      interactionType: 'summary',

      content: text,

      modelUsed: _lastModel,

      sources: sources,

      simulation: sim,
    );
  }

  Future<AiResponse> generateQuiz({
    required AppUser? user,

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    int numQuestions = 5,

    String languageCode = 'en',
  }) async {
    final c = await _ctx(user);

    final t = await _topic(progressionId);

    final tl = _topicLine(t, subjectName, topicTitle, languageCode);

    final fr = languageCode == 'fr';

    final langPromptHeader = fr
        ? '[LANGUE OBLIGATOIRE : FRANÇAIS - Toutes les questions, options de réponse, énoncés et explications doivent être STRICTEMENT et ENTIÈREMENT rédigés en français. Il est formellement interdit d\'écrire en anglais.]\n\n'
        : '[MANDATORY LANGUAGE: ENGLISH - All questions, answer options, statements, and explanations MUST BE STRICTLY AND ENTIRELY WRITTEN IN ENGLISH. It is strictly forbidden to output in French.]\n\n';

    final prompt =
        '''
$langPromptHeader$tl

${fr ? 'Génère' : 'Generate'} $numQuestions ${fr ? 'questions de quiz sur ce chapitre, STRICTEMENT en français' : 'quiz questions on this topic, STRICTLY in English'}.

${fr ? 'Réponds UNIQUEMENT avec du JSON valide de la forme' : 'Reply ONLY with valid JSON of the form'}:

{"intro":"${fr ? 'phrase d\'introduction courte en français' : 'short intro sentence in English'}","quiz":[{"question":"...","question_type":"mcq","options":["A","B","C","D"],"correct_index":0,"marks":1,"expected_points":[],"explanation":"..."}]}

${fr ? 'Chaque question a exactement 4 options et correct_index est l\'indice (0-3) de la bonne réponse. Toutes les options doivent être rédigées en français.' : 'Every question has exactly 4 options and correct_index is the (0-3) index of the right answer. All options must be written in English.'}

''';

    final raw = await _gemini(
      [
        {'text': prompt},
      ],
      json: true,
      system: _system(c, languageCode),
    );

    Map<String, dynamic> parsed;

    try {
      parsed =
          jsonDecode(raw.replaceAll(RegExp(r'^```json\s*|```\s*$'), '').trim())
              as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Le quiz généré est invalide, réessayez.');
    }

    final quiz = (parsed['quiz'] as List?) ?? [];

    if (quiz.isEmpty) throw Exception('Aucune question générée, réessayez.');

    final intro =
        (parsed['intro'] ?? (fr ? 'Voici votre quiz.' : 'Here is your quiz.'))
            .toString();

    await _save(user, progressionId, 'quiz', tl, intro);

    return AiResponse.fromJson({
      'interaction_type': 'quiz',

      'content': intro,

      'model_used': _lastModel,

      'quiz': quiz,
    });
  }

  Future<AiResponse> gradeQuizSubmission({
    required AppUser? user,

    required List<QuizQuestion> quiz,

    required Map<String, dynamic> typedAnswers,

    int? progressionId,

    String? subjectName,

    String? topicTitle,

    String note = '',

    List<({String name, List<int> bytes})> paperImages = const [],

    String languageCode = 'en',
  }) async {
    final c = await _ctx(user);

    final t = await _topic(progressionId);

    final tl = _topicLine(t, subjectName, topicTitle, languageCode);

    final fr = languageCode == 'fr';

    final qjson = jsonEncode([
      for (var i = 0; i < quiz.length; i++)
        {
          'id': 'Q${i + 1}',

          'question': quiz[i].question,

          'type': quiz[i].questionType,

          'options': quiz[i].options,

          'correct_answer':
              quiz[i].isMcq && quiz[i].correctIndex < quiz[i].options.length
              ? quiz[i].options[quiz[i].correctIndex]
              : null,

          'expected_points': quiz[i].expectedPoints,

          'marks': quiz[i].marks,
        },
    ]);

    final prompt =
        '''

$tl

${fr ? 'Corrige la copie de l\'élève.' : 'Mark the student\'s work.'}

QUIZ: $qjson

${fr ? 'RÉPONSES DE L\'ÉLÈVE' : 'STUDENT ANSWERS'}: ${jsonEncode(typedAnswers)}

${note.trim().isEmpty ? '' : '${fr ? 'NOTE DE L\'ÉLÈVE' : 'STUDENT NOTE'}: $note'}

${paperImages.isEmpty ? '' : (fr ? 'Des photos de la copie papier sont jointes.' : 'Photos of the paper answers are attached.')}

${fr ? 'Réponds UNIQUEMENT en JSON' : 'Reply ONLY in JSON'}: {"score": <points obtenus>, "total": <points possibles>, "feedback": "${fr ? 'correction détaillée question par question en markdown, avec encouragements' : 'detailed question-by-question feedback in markdown with encouragement'}", "weak_points": ["..."]}

''';

    final raw = await _gemini(
      [
        {'text': prompt},

        for (final f in paperImages)
          {
            'inlineData': {
              'mimeType': _mimeOf(f.name),
              'data': base64.encode(f.bytes),
            },
          },
      ],
      json: true,
      system: _system(c, languageCode),
    );

    Map<String, dynamic> g;

    try {
      g =
          jsonDecode(raw.replaceAll(RegExp(r'^```json\s*|```\s*$'), '').trim())
              as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Correction impossible pour le moment, réessayez.');
    }

    final total = ((g['total'] as num?) ?? quiz.length).toDouble();

    final score = ((g['score'] as num?) ?? 0).toDouble();

    final pct = total <= 0 ? 0 : (score / total * 100).round();

    final feedback = (g['feedback'] ?? '').toString();

    final scoreTxt = score == score.roundToDouble()
        ? score.round().toString()
        : score.toStringAsFixed(1);

    final totalTxt = total == total.roundToDouble()
        ? total.round().toString()
        : total.toStringAsFixed(1);

    var updated = false;

    if (user != null && progressionId != null) {
      final weak = ((g['weak_points'] as List?) ?? []).join('; ');

      final status = pct >= 80
          ? 'understood'
          : (pct >= 50 ? 'in_progress' : 'needs_revision');

      final level = pct >= 80 ? 'full' : (pct >= 50 ? 'partial' : 'none');

      try {
        final r = await http.post(
          _u('/student_topic_progress', {
            'on_conflict': 'user_id,progression_id',
          }),

          headers: {
            ..._h,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },

          body: jsonEncode({
            'user_id': user.id,

            'progression_id': progressionId,

            'status': status,

            'understanding_level': level,

            'quiz_score': pct.clamp(0, 100),

            'weakness_notes': weak,

            'last_studied_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );

        updated = r.statusCode < 300;
      } catch (_) {}
    }

    await _save(
      user,
      progressionId,
      'check',
      'Quiz ${tl.isEmpty ? '' : tl}',
      feedback,
    );

    return AiResponse.fromJson({
      'interaction_type': 'check',

      'content': feedback,

      'model_used': _lastModel,

      'score_summary': '$scoreTxt/$totalTxt ($pct%)',

      'progress_updated': updated,
    });
  }

  Future<String> translateText({
    required String text,
    required String targetLanguage,
  }) async {
    final langName = targetLanguage == 'fr' ? 'French' : 'English';
    final out = await _gemini([
      {
        'text':
            'Translate the following educational/academic text into $langName. Adjust any language self-references to match $langName. Keep the exact formatting, steps, math numbers and formulas. Output ONLY the translation without any preamble:\n\n$text',
      },
    ]);

    return cleanMathNotation(out.trim(), '', targetLanguage == 'fr');
  }

  Future<List<QuizQuestion>> translateQuiz({
    required List<QuizQuestion> quiz,
    required String targetLanguage,
  }) async {
    if (quiz.isEmpty) return quiz;
    final langName = targetLanguage == 'fr' ? 'French' : 'English';
    final rawQuizJson = jsonEncode(quiz.map((q) => q.toJson()).toList());
    final prompt = '''
Translate the following quiz questions, choices/options, and explanations into $langName.
CRITICAL: Keep the exact same JSON list structure, fields ('question', 'question_type', 'options', 'correct_index', 'marks', 'expected_points', 'explanation'), correct_index values, and question counts.
Output ONLY the raw JSON list:

$rawQuizJson
''';
    try {
      final out = await _gemini([{'text': prompt}], json: true);
      final decoded = jsonDecode(out.replaceAll(RegExp(r'^```json\s*|```\s*$'), '').trim());
      if (decoded is List) {
        return decoded
            .map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return quiz;
  }

  Future<({String text, String modelUsed})> transcribeAudio({
    required String filename,

    required List<int> bytes,

    String language = 'en',
  }) async {
    final out = await _gemini([
      {
        'text':
            'Transcribe this audio exactly as spoken (language: ${language == 'fr' ? 'French' : 'English'}). Output ONLY the transcription text.',
      },

      {
        'inlineData': {
          'mimeType': _mimeOf(filename),
          'data': base64.encode(bytes),
        },
      },
    ]);

    return (text: out.trim(), modelUsed: _lastModel);
  }

  static final Map<int, Map<String, dynamic>> _historyTopicCache = {};

  Future<List<AiHistoryItem>> getAiHistory(
    AppUser user, {
    int limit = 25,
  }) async {
    final rows = await _list('/ai_interactions', {
      'user_id': 'eq.${user.id}',
      'order': 'id.desc',
      'limit': '$limit',
      'select': '*',
    });

    final missingIds = rows
        .map((r) => (r['progression_id'] as num?)?.toInt())
        .whereType<int>()
        .where((id) => !_historyTopicCache.containsKey(id))
        .toSet()
        .toList();

    if (missingIds.isNotEmpty) {
      try {
        final tr = await _list('/official_progressions', {
          'id': 'in.(${missingIds.join(',')})',
          'select': 'id,subject_name,topic_title',
        });

        for (final t in tr) {
          _historyTopicCache[(t['id'] as num).toInt()] =
              t as Map<String, dynamic>;
        }
      } catch (_) {}
    }

    return rows.map((r) {
      final pid = (r['progression_id'] as num?)?.toInt();

      return AiHistoryItem.fromJson({
        'id': r['id'],

        'progression_id': pid,

        'subject_name': (pid == null
            ? null
            : _historyTopicCache[pid])?['subject_name'],

        'topic_title': (pid == null
            ? null
            : _historyTopicCache[pid])?['topic_title'],

        'interaction_type': r['interaction_type'],

        'prompt': r['prompt'],

        'response': cleanMathNotation(r['response']?.toString() ?? ''),

        'created_at': r['created_at'],
      });
    }).toList();
  }

  Future<bool> deleteAiHistoryItem(AppUser user, int id) async {
    final r = await http.delete(
      _u('/ai_interactions', {'id': 'eq.$id', 'user_id': 'eq.${user.id}'}),
      headers: _h,
    );

    return r.statusCode < 300;
  }

  Future<bool> clearAiHistory(AppUser user) async {
    final r = await http.delete(
      _u('/ai_interactions', {'user_id': 'eq.${user.id}'}),
      headers: _h,
    );

    return r.statusCode < 300;
  }

  // ===================================================================

  // Background notifications digest (works with the app closed)

  // ===================================================================

  Future<Map<String, dynamic>> backgroundDigestForUserId(int userId) async {
    final user = await getMe(
      current: AppUser(
        id: userId,
        fullName: '',
        email: '',
        role: 'student',
        questionnaireCompleted: true,
      ),
    );

    final home = await _cloud.getStudentHome(user);

    final now = DateTime.now();

    final isSunday = now.weekday == DateTime.sunday;

    String line(OfficialProgression p) => '${p.subjectName}: ${p.topicTitle}';

    final today = home.todayTopics.take(4).map(line).join(', ');

    final week = home.weeklyTopics.take(5).map(line).join('; ');

    return {
      'is_sunday': isSunday,

      'sunday_title': 'Kivora — programme de la semaine',

      'sunday_body': week.isEmpty
          ? 'Ouvrez Kivora pour préparer votre semaine avec votre tuteur IA.'
          : 'Cette semaine : $week',

      'daily_title': 'Kivora — à étudier aujourd\'hui',

      'daily_body': today.isEmpty
          ? 'Ouvrez Kivora pour étudier vos sujets avec votre tuteur IA.'
          : 'Aujourd\'hui : $today',
    };
  }
}
