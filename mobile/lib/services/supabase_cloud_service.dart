import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/study_models.dart';

String cleanSubjectName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  // 1. Strip French series or class prefixes (e.g. 'ABI - ', 'A - ', 'AC - ', 'Classe de 6ème - ')
  final prefixRe = RegExp(r'^(Classe de \d+ème|Première [A-Za-z]+|\d+ème année|[A-Z]{1,4})\s*-\s*', caseSensitive: false);
  final m = prefixRe.firstMatch(s);
  if (m != null) {
    s = s.substring(m.end).trim();
  }

  // 2. Strip track / specialization suffixes (e.g. ' - Tertiary Sciences...', ' - Industrial Techniques...')
  if (s.contains(' - ')) {
    s = s.split(' - ')[0].trim();
  }

  // 3. Strip noise like '(ID-965)' or trailing ' ok'
  s = s.replaceAll(RegExp(r'\(ID-\d+\)', caseSensitive: false), '').trim();
  if (s.toLowerCase().endsWith(' ok')) {
    s = s.substring(0, s.length - 3).trim();
  }

  final low = s.toLowerCase();
  if (low.startsWith('commerce stt')) {
    return 'Commerce';
  }
  if (low.contains('fran') || low == 'french') {
    return 'Français';
  }
  return s;
}

String localizeSubject(String raw, bool isFr) {
  var s = cleanSubjectName(raw);
  if (s.isEmpty) return '';
  final low = s.toLowerCase();

  if (isFr) {
    if (low.contains('manual labour') || low.contains('handicraft') || low.contains('manual labor')) {
      if (low.contains('animal')) return 'Travail manuel (Production Animale)';
      if (low.contains('crop') || low.contains('plant') || low.contains('veget')) return 'Travail manuel (Production Végétale)';
      return 'Travail manuel (Artisanat)';
    }
    if (low.contains('guidance') || low.contains('counselling')) return 'Orientation Conseil';
    if (low.contains('business management')) return 'Gestion d\'entreprise';
    if (low.contains('business math')) return 'Mathématiques de gestion';
    if (low.contains('applied steno') || low.contains('stenotypy')) return 'Sténotypie appliquée';
    if (low.contains('material management')) return 'Gestion des matières';
    if (low.contains('stock management')) return 'Gestion des stocks';
    if (low.contains('automated system')) return 'Systèmes automatisés';
    if (low.contains('accounting')) return 'Comptabilité';
    if (low.contains('commerce') || low.contains('finance')) return 'Commerce et Finance';
    if (low.contains('chemistry')) return 'Chimie';
    if (low.contains('biology')) return 'Biologie';
    if (low.contains('physics')) return 'Physique';
    if (low.contains('mathematics') || low.contains('maths')) return 'Mathématiques';
    if (low.contains('computer science') || low.contains('ict')) return 'Informatique';
    if (low.contains('history')) return 'Histoire';
    if (low.contains('geography')) return 'Géographie';
    if (low.contains('philosophy')) return 'Philosophie';
    if (low.contains('economics')) return 'Économie';
    if (low.contains('citizenship')) return 'Éducation à la citoyenneté';
    if (low.contains('fashion') || low.contains('clothing')) return 'Dessin de Mode';
    if (low.contains('science')) return 'Sciences';
    if (low.contains('french')) return 'Français';
    if (low.contains('english')) return 'Anglais';
    return s;
  } else {
    // English target
    if (low.contains('travail manuel')) {
      if (low.contains('artisanat')) return 'Manual Labour (Handicraft)';
      if (low.contains('animal') || low.contains('animale')) return 'Manual Labour (Animal Husbandry)';
      if (low.contains('veget') || low.contains('végét')) return 'Manual Labour (Crop Production)';
      return 'Manual Labour (Handicraft)';
    }
    if (low.contains('orientation') || low.contains('conseil')) return 'Guidance & Counselling';
    if (low.contains('gestion d\'entreprise') || low.contains('organisation')) return 'Business Management';
    if (low.contains('gestion des mat') || low.contains('matieres') || low.contains('matières')) return 'Material Management';
    if (low.contains('gestion des stocks')) return 'Stock Management';
    if (low.contains('sténotypie') || low.contains('stenotypie')) return 'Applied Stenotypy';
    if (low.contains('systèmes automatisés') || low.contains('systemes automatises')) return 'Automated Systems';
    if (low.contains('comptabilit')) return 'Accounting';
    if (low.contains('commerce')) return 'Commerce & Finance';
    if (low.contains('chimie')) return 'Chemistry';
    if (low.contains('biologie') || low.contains('svteehb') || low.contains('svt')) return 'Biology';
    if (low.contains('physique')) return 'Physics';
    if (low.contains('mathématique') || low.contains('mathematique')) return 'Mathematics';
    if (low.contains('informatique')) return 'Computer Science';
    if (low.contains('histoire')) return 'History';
    if (low.contains('géographie') || low.contains('geographie')) return 'Geography';
    if (low.contains('philosophie')) return 'Philosophy';
    if (low.contains('économie') || low.contains('economie')) return 'Economics';
    if (low.contains('citoyenneté') || low.contains('citoyennete')) return 'Citizenship Education';
    if (low.contains('dessin de mode')) return 'Fashion Drawing';
    if (low.contains('sciences') || low.contains('science')) return 'Sciences';
    if (low.contains('français') || low.contains('francais')) return 'French';
    if (low.contains('anglais')) return 'English';
    return s;
  }
}

String localizeTopicTitle(String raw, bool isFr) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  if (isFr) {
    s = s.replaceAll(RegExp(r'^Lesson\s+', caseSensitive: false), 'Leçon ');
    s = s.replaceAll(RegExp(r'^Chapter\s+', caseSensitive: false), 'Chapitre ');
    s = s.replaceAll(RegExp(r'^Unit\s+', caseSensitive: false), 'Unité ');
    s = s.replaceAll(RegExp(r'\bSession\s+(\d+)', caseSensitive: false), 'Séance \$1');
    s = s.replaceAll(RegExp(r'\bIntroduction to\b', caseSensitive: false), 'Introduction à');
    s = s.replaceAll(RegExp(r'\bRadioactivity\b', caseSensitive: false), 'La radioactivité');
    s = s.replaceAll(RegExp(r'\bFactor Theorem\b', caseSensitive: false), 'Théorème du facteur');
    s = s.replaceAll(RegExp(r'\bPolynomials\b', caseSensitive: false), 'Polynômes');
    s = s.replaceAll(RegExp(r'\bTypes and forms of portrait representation\b', caseSensitive: false), 'LES Types et formes de représentation des portraits');
    s = s.replaceAll(RegExp(r'\bPig farming\b', caseSensitive: false), 'L\'élevage des porcs');
  } else {
    s = s.replaceAll(RegExp(r'^Leçon\s+', caseSensitive: false), 'Lesson ');
    s = s.replaceAll(RegExp(r'^Chapitre\s+', caseSensitive: false), 'Chapter ');
    s = s.replaceAll(RegExp(r'^Unité\s+', caseSensitive: false), 'Unit ');
    s = s.replaceAll(RegExp(r'\bSéance\s+(\d+)', caseSensitive: false), 'Session \$1');
    s = s.replaceAll(RegExp(r"\bIntroduction à l[’']élevage des porcs\b", caseSensitive: false), 'Introduction to pig farming');
    s = s.replaceAll(RegExp(r'\bIdentification de la race de porcs à élever, et du site\b', caseSensitive: false), 'Breed and site selection for pig farming');
    s = s.replaceAll(RegExp(r'\bLES Types et formes de représentation des portraits\b', caseSensitive: false), 'Types and forms of portrait representation');
    s = s.replaceAll(RegExp(r'\bLa radioactivité\b', caseSensitive: false), 'Radioactivity');
    s = s.replaceAll(RegExp(r'\bThéorème du facteur\b', caseSensitive: false), 'Factor Theorem');
    s = s.replaceAll(RegExp(r'\bPolynômes\b', caseSensitive: false), 'Polynomials');
  }
  return s;
}

String cleanMathNotation(String raw, [String? studentName, bool isFr = false]) {
  var s = raw;

  // Personalize greeting if studentName is supplied
  final name = (studentName ?? '').trim();
  if (name.isNotEmpty && name.toLowerCase() != 'student') {
    final firstName = name.split(RegExp(r'\s+')).first;
    final capName = firstName[0].toUpperCase() + firstName.substring(1);
    final target = isFr ? 'Bonjour $capName !' : 'Good morning, $capName!';
    s = s.replaceAll(
      RegExp(r'\b(Good morning|Welcome|Hello),?\s+(?:class|everyone|students)\s*!?', caseSensitive: false),
      target,
    );
    s = s.replaceAll(
      RegExp(r'\b(Bonjour|Bienvenue)\s+(?:la classe|à tous|chers élèves)\s*!?', caseSensitive: false),
      target,
    );
  }

  // 1. Strip raw LaTeX text commands like \text{...}, \mathrm{...}, \mathbf{...}, \mathit{...}
  s = s.replaceAllMapped(
    RegExp(r'\\(?:text|mathrm|mathbf|mathit)\{([^{}]+)\}'),
    (m) => m.group(1) ?? '',
  );

  // 2. Convert common LaTeX math operators, fractions, square roots and dots
  s = s.replaceAllMapped(
    RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
    (m) => '(${m.group(1)} / ${m.group(2)})',
  );
  s = s.replaceAllMapped(
    RegExp(r'\\sqrt\{([^{}]+)\}'),
    (m) => '√(${m.group(1)})',
  );
  s = s.replaceAll(r'\dots', '...');
  s = s.replaceAll(r'\ldots', '...');
  s = s.replaceAll(r'\cdots', '...');

  const replacements = {
    r'\implies': '⇒',
    r'\impliedby': '⇐',
    r'\iff': '⇔',
    r'\in': '∈',
    r'\notin': '∉',
    r'\subset': '⊂',
    r'\subseteq': '⊆',
    r'\cup': '∪',
    r'\cap': '∩',
    r'\forall': '∀',
    r'\exists': '∃',
    r'\empty': '∅',
    r'\emptyset': '∅',
    r'^\circ': '°',
    r'\degree': '°',
    r'\circ': '°',
    r'\times': '×',
    r'\cdot': '·',
    r'\div': '÷',
    r'\pm': '±',
    r'\leq': '≤',
    r'\le': '≤',
    r'\geq': '≥',
    r'\ge': '≥',
    r'\neq': '≠',
    r'\ne': '≠',
    r'\approx': '≈',
    r'\sim': '~',
    r'\infty': '∞',
    r'\pi': 'π',
    r'\theta': 'θ',
    r'\alpha': 'α',
    r'\beta': 'β',
    r'\gamma': 'γ',
    r'\Delta': 'Δ',
    r'\delta': 'δ',
    r'\lambda': 'λ',
    r'\mu': 'μ',
    r'\sigma': 'σ',
    r'\omega': 'ω',
    r'\Omega': 'Ω',
    r'\Rightarrow': '⇒',
    r'\rightarrow': '→',
    r'\to': '→',
    r'\leftarrow': '←',
    r'\leftrightarrow': '↔',
    r'\left(': '(',
    r'\right)': ')',
    r'\left[': '[',
    r'\right]': ']',
    r'\left\{': '{',
    r'\right\}': '}',
  };
  replacements.forEach((k, v) {
    s = s.replaceAll(k, v);
  });

  // Strip math delimiter dollar signs ($x = 2$ -> x = 2, $$ -> empty)
  s = s.replaceAll(r'$$', '');
  s = s.replaceAllMapped(RegExp(r'(?<!\\)\$([^$\n]+)\$'), (m) => m.group(1) ?? '');

  // Unicode superscripts and subscripts maps
  const supMap = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', 'n': 'ⁿ', 'x': 'ˣ', 'y': 'ʸ', 'm': 'ᵐ',
  };
  const subMap = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', 'a': 'ₐ', 'e': 'ₑ', 'i': 'ᵢ',
    'o': 'ₒ', 'u': 'ᵤ', 'x': 'ₓ',
  };

  String toSuperscript(String src) =>
      src.split('').map((c) => supMap[c] ?? c).join();
  String toSubscript(String src) =>
      src.split('').map((c) => subMap[c] ?? c).join();

  // 3. Handle combined isotope notation: ^{238}_{92} or ^4_2 or ^{14}_{6}
  s = s.replaceAllMapped(
    RegExp(r'\^\{([0-9+-]+)\}_\{([0-9+-]+)\}|\^([0-9+-]+)_([0-9+-]+)'),
    (m) {
      final sup = m.group(1) ?? m.group(3) ?? '';
      final sub = m.group(2) ?? m.group(4) ?? '';
      return '${toSuperscript(sup)}${toSubscript(sub)}';
    },
  );

  // 4. Multi-digit or single-digit superscripts: ^{238}, ^2, ^3, etc.
  s = s.replaceAllMapped(
    RegExp(r'\^\{([0-9+-nxy]+)\}|\^([0-9nxy])'),
    (m) {
      final key = m.group(1) ?? m.group(2) ?? '';
      return toSuperscript(key);
    },
  );

  // 5. Multi-digit or single-digit subscripts: _{92}, _2, _3, etc.
  s = s.replaceAllMapped(
    RegExp(r'_\{([0-9+-aeioux]+)\}|_([0-9])'),
    (m) {
      final key = m.group(1) ?? m.group(2) ?? '';
      return toSubscript(key);
    },
  );

  // 6. Remove LaTeX inline/display $...$ / $$...$$ delimiters cleanly.
  s = s.replaceAll(r'$$', '');
  s = s.replaceAllMapped(
    RegExp(r'\$([^$\n]{1,160})\$'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAll(r'$', '');

  // 7. Clean markdown checkboxes into neat symbols.
  s = s.replaceAll('[ ] ', '☐ ');
  s = s.replaceAll('[x] ', '☑ ');
  s = s.replaceAll('[X] ', '☑ ');
  return s;
}

int daySlotForProgression(String studyDays, String subjectName) {
  final d = studyDays.toLowerCase().trim();
  final isGeneric = d.isEmpty ||
      d.contains("mon - fri") ||
      d.contains("mon-fri") ||
      d.contains("lun - ven") ||
      d.contains("lun-ven") ||
      d.contains("all week") ||
      d.contains("toute la semaine") ||
      d.contains("tous les jours");

  if (!isGeneric) {
    if (d.contains("lundi") || d.contains("monday")) return 0;
    if (d.contains("mardi") || d.contains("tuesday")) return 1;
    if (d.contains("mercredi") || d.contains("wednesday")) return 2;
    if (d.contains("jeudi") || d.contains("thursday")) return 3;
    if (d.contains("vendredi") || d.contains("friday")) return 4;
    if (d.contains("samedi") || d.contains("saturday") || d.contains("dimanche") || d.contains("sunday") || d.contains("revision")) return 5;
  }

  final s = subjectName.toLowerCase();
  if (s.contains("math") || s.contains("algè") || s.contains("angl") || s.contains("eng")) return 0;
  if (s.contains("eco") || s.contains("comm") || s.contains("geog") || s.contains("géo") || s.contains("busi")) return 1;
  if (s.contains("bio") || s.contains("chim") || s.contains("chem") || s.contains("phys") || s.contains("scie")) return 2;
  if (s.contains("hist") || s.contains("citi") || s.contains("fran") || s.contains("civi") || s.contains("droit") || s.contains("litt")) return 3;
  if (s.contains("info") || s.contains("comp") || s.contains("art") || s.contains("tech") || s.contains("dess") || s.contains("tailor") || s.contains("fash") || s.contains("food") || s.contains("manu")) return 4;
  return (subjectName.hashCode.abs()) % 5;
}

class SupabaseCloudService {
  static const String supabaseUrl = 'https://xlbkroltpafksdivwhtz.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_s6o_FKvToWoChdrynWnURA_3Ko33auB';
  static String get geminiApiKey {
    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return utf8.decode(base64.decode('QVEuQWI4Uk42SzJlczlOWTdIMXlJUkZ5b1NHSFVRQ1VBQU51NlFBNmdCVXNCUlI1YzNtNkE='));
  }
  static const String geminiModel = 'gemini-3.1-flash-lite';

  Map<String, String> get _headers => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer $supabaseAnonKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Prefer': 'return=representation',
      };

  Uri _restUri(String path, [Map<String, dynamic>? query]) {
    final queryStr = query != null
        ? query.entries
            .map((e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}')
            .join('&')
        : null;
    final url = '$supabaseUrl/rest/v1$path${queryStr != null ? '?$queryStr' : ''}';
    return Uri.parse(url);
  }

  // Password verification & hashing byte-for-byte compatible with Python PBKDF2-HMAC-SHA256
  static List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final numBlocks = (keyLength + 31) ~/ 32;
    final result = Uint8List(keyLength);
    var outOffset = 0;

    for (var block = 1; block <= numBlocks; block++) {
      final blockBytes = ByteData(4)..setUint32(0, block, Endian.big);
      final saltWithBlock = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..setRange(salt.length, salt.length + 4, blockBytes.buffer.asUint8List());

      var u = hmac.convert(saltWithBlock).bytes;
      final blockResult = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < blockResult.length; k++) {
          blockResult[k] ^= u[k];
        }
      }

      final toCopy = (outOffset + 32 > keyLength) ? keyLength - outOffset : 32;
      result.setRange(outOffset, outOffset + toCopy, blockResult);
      outOffset += toCopy;
    }
    return result;
  }

  static String hashPassword(String password) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final digest = _pbkdf2(utf8.encode(password), salt, 120000, 32);
    return '${base64.encode(salt)}\$${base64.encode(digest)}';
  }

  static bool verifyPassword(String password, String storedHash) {
    try {
      final parts = storedHash.split('\$');
      if (parts.length != 2) return false;
      final salt = base64.decode(parts[0]);
      final expected = base64.decode(parts[1]);
      final actual = _pbkdf2(utf8.encode(password), salt, 120000, 32);
      if (actual.length != expected.length) return false;
      var match = 0;
      for (var i = 0; i < actual.length; i++) {
        match |= actual[i] ^ expected[i];
      }
      return match == 0;
    } catch (_) {
      return false;
    }
  }

  static String classNameFor(int? id) {
    if (id == null) return '';
    const classNames = {
      1: 'Form 1',
      2: 'Form 2',
      3: 'Form 3',
      4: 'Form 4',
      5: 'Form 5',
      6: 'Lower Sixth',
      7: 'Upper Sixth',
      8: '6eme',
      9: '5eme',
      10: '4eme',
      11: '3eme',
      12: 'Seconde',
      13: 'Premiere',
      14: 'Terminale',
    };
    return classNames[id] ?? 'Classe $id';
  }

  static String subsystemNameFor(int? id) {
    if (id == null) return '';
    return id == 1 ? 'Anglophone' : 'Francophone';
  }

  // --- AUTHENTICATION ---
  Future<(String, AppUser)> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await http.get(
      _restUri('/users', {'email': 'eq.$cleanEmail', 'select': '*'}),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Supabase connection error: ${res.statusCode}');
    }
    final List list = jsonDecode(res.body);
    if (list.isEmpty) {
      throw Exception('Compte introuvable pour cet email.');
    }
    final userRow = list.first as Map<String, dynamic>;
    final storedHash = userRow['password_hash'] as String? ?? '';
    if (!verifyPassword(password, storedHash)) {
      throw Exception('Mot de passe incorrect.');
    }

    if (userRow['is_active'] == false) {
      throw Exception('Compte désactivé par l\'administrateur.');
    }
    final userId = (userRow['id'] as num).toInt();
    final role = userRow['role'] as String? ?? 'student';

    bool questionnaireCompleted = true;
    if (role == 'student') {
      final profRes = await http.get(
        _restUri('/student_profiles',
            {'user_id': 'eq.$userId', 'select': 'questionnaire_completed'}),
        headers: _headers,
      );
      if (profRes.statusCode == 200) {
        final profList = jsonDecode(profRes.body) as List;
        if (profList.isNotEmpty) {
          questionnaireCompleted =
              profList.first['questionnaire_completed'] as bool? ?? false;
        }
      }
    }

    final appUser = AppUser(
      id: userId,
      fullName: userRow['full_name'] as String? ?? '',
      email: cleanEmail,
      role: role,
      questionnaireCompleted: questionnaireCompleted,
    );

    // Dummy signed token for mobile session
    final token = base64Url.encode(utf8.encode('user:$userId:$role'));
    return (token, appUser);
  }

  Future<(String, AppUser)> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    // Check if exists
    final checkRes = await http.get(
      _restUri('/users', {'email': 'eq.$cleanEmail', 'select': 'id'}),
      headers: _headers,
    );
    if (checkRes.statusCode == 200) {
      final list = jsonDecode(checkRes.body) as List;
      if (list.isNotEmpty) {
        throw Exception('Cet email est déjà enregistré.');
      }
    }

    final pwHash = hashPassword(password);
    final insertUserRes = await http.post(
      _restUri('/users'),
      headers: _headers,
      body: jsonEncode({
        'full_name': fullName.trim(),
        'email': cleanEmail,
        'password_hash': pwHash,
        'role': role,
        'is_active': true,
      }),
    );
    if (insertUserRes.statusCode != 201 && insertUserRes.statusCode != 200) {
      throw Exception(
          'Erreur lors de la création du compte: ${insertUserRes.body}');
    }

    final insertedUser = (jsonDecode(insertUserRes.body) as List).first;
    final userId = (insertedUser['id'] as num).toInt();

    if (role == 'student') {
      await http.post(
        _restUri('/student_profiles'),
        headers: _headers,
        body: jsonEncode({
          'user_id': userId,
          'questionnaire_completed': false,
        }),
      );
    }

    final appUser = AppUser(
      id: userId,
      fullName: fullName.trim(),
      email: cleanEmail,
      role: role,
      questionnaireCompleted: role != 'student',
    );

    final token = base64Url.encode(utf8.encode('user:$userId:$role'));
    return (token, appUser);
  }

  // --- SUBSYSTEMS & CLASSES ---
  Future<List<Subsystem>> getSubsystems() async {
    final res = await http.get(
      _restUri('/subsystems', {'select': '*,classes(*)'}),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Impossible de charger les sous-systèmes.');
    }
    final List list = jsonDecode(res.body);
    return list.map((s) => Subsystem.fromJson(s as Map<String, dynamic>)).toList();
  }

  // --- QUESTIONNAIRE ---
  Future<StudentProfile> saveQuestionnaire({
    String? fullName,
    required int userId,
    required int subsystemId,
    required int classId,
    required int age,
    required String favouriteSubject,
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
    final body = {
      'user_id': userId,
      'subsystem_id': subsystemId,
      'class_id': classId,
      'age': age,
      'questionnaire_completed': true,
      'favourite_subject': favouriteSubject,
      'subjects_json': jsonEncode(offeredSubjects ?? []),
      'difficult_subjects_json': jsonEncode(difficultSubjects),
      'difficulty_reason': difficultyReason ?? '',
      'hobbies_json': jsonEncode(hobbies),
      'activity_style': activityStyle,
      'learning_style': learningStyle,
      'fallback_preference': fallbackPreference,
      'exercise_preference': exercisePreference,
      'preferred_study_period': preferredStudyPeriod,
      'academic_goal': academicGoal ?? '',
      'daily_goal_minutes': dailyGoalMinutes,
      'reminder_hour': reminderHour,
      'reminder_minute': reminderMinute,
    };

    if (fullName != null && fullName.trim().isNotEmpty) {
      await http.patch(
        _restUri('/users', {'id': 'eq.$userId'}),
        headers: _headers,
        body: jsonEncode({'full_name': fullName.trim()}),
      );
    }

    final headersWithUpsert = Map<String, String>.from(_headers)
      ..['Prefer'] = 'resolution=merge-duplicates,return=representation';

    final res = await http.post(
      _restUri('/student_profiles'),
      headers: headersWithUpsert,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Erreur sauvegarde profil: ${res.body}');
    }

    return StudentProfile(
      userId: userId,
      subsystemId: subsystemId,
      subsystemName: subsystemNameFor(subsystemId),
      classId: classId,
      className: classNameFor(classId),
      age: age,
      questionnaireCompleted: true,
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
      offeredSubjects: offeredSubjects ?? [],
    );
  }

  // --- STUDENT HOME & CURRICULUM ---
  Future<StudentHomeData> getStudentHome(AppUser user) async {
    // 1. Get profile
    final profRes = await http.get(
      _restUri('/student_profiles', {'user_id': 'eq.${user.id}', 'select': '*'}),
      headers: _headers,
    );
    if (profRes.statusCode != 200) {
      throw Exception('Erreur chargement profil étudiant.');
    }
    final profList = jsonDecode(profRes.body) as List;
    if (profList.isEmpty) {
      throw Exception('Profil introuvable pour cet utilisateur.');
    }
    final pMap = profList.first as Map<String, dynamic>;
    final classId = (pMap['class_id'] as num?)?.toInt() ?? 1;
    final subsystemId = (pMap['subsystem_id'] as num?)?.toInt() ?? 1;

    // Parse JSON arrays for subjects / hobbies
    List<String> parseList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val.map((e) => e.toString()).toList();
      try {
        final decoded = jsonDecode(val.toString());
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
      return [];
    }

    final offeredList = parseList(pMap['subjects_json']);
    final cleanOffered = offeredList.map(cleanSubjectName).where((s) => s.length > 1).toSet();

    final profile = StudentProfile(
      userId: user.id,
      subsystemId: subsystemId,
      subsystemName: subsystemNameFor(subsystemId),
      classId: classId,
      className: classNameFor(classId),
      age: (pMap['age'] as num?)?.toInt(),
      questionnaireCompleted: pMap['questionnaire_completed'] as bool? ?? false,
      favouriteSubject: pMap['favourite_subject'] as String?,
      difficultSubjects: parseList(pMap['difficult_subjects_json']),
      difficultyReason: pMap['difficulty_reason'] as String?,
      hobbies: parseList(pMap['hobbies_json']),
      activityStyle: pMap['activity_style'] as String? ?? 'both',
      learningStyle: pMap['learning_style'] as String? ?? 'practical_examples',
      fallbackPreference:
          pMap['fallback_preference'] as String? ?? 'another_example',
      exercisePreference:
          pMap['exercise_preference'] as String? ?? 'short_quizzes',
      preferredStudyPeriod:
          pMap['preferred_study_period'] as String? ?? 'evening',
      academicGoal: pMap['academic_goal'] as String?,
      dailyGoalMinutes: (pMap['daily_goal_minutes'] as num?)?.toInt() ?? 60,
      reminderHour: (pMap['reminder_hour'] as num?)?.toInt() ?? 18,
      reminderMinute: (pMap['reminder_minute'] as num?)?.toInt() ?? 0,
      offeredSubjects: offeredList,
    );

    // 2. Fetch Progressions for this class
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    Future<List> fetchProg(Map<String, dynamic> q) async {
      final r = await http.get(_restUri('/official_progressions', q),
          headers: _headers);
      return r.statusCode == 200 ? (jsonDecode(r.body) as List) : [];
    }

    var progList = await fetchProg({
      'class_id': 'eq.$classId',
      'start_date': 'lte.$todayIso',
      'end_date': 'gte.$todayIso',
      'order': 'week_number.asc,subject_name.asc',
      'limit': '3000',
    });
    if (progList.isEmpty) {
      progList = await fetchProg({
        'class_id': 'eq.$classId',
        'start_date': 'lte.$todayIso',
        'order': 'start_date.desc,subject_name.asc',
        'limit': '3000',
      });
    }
    if (progList.isEmpty) {
      progList = await fetchProg({
        'class_id': 'eq.$classId',
        'order': 'week_number.asc,subject_name.asc',
        'limit': '3000',
      });
    }

    // 3. Fetch Student's Topic Progress
    final progressRes = await http.get(
      _restUri(
          '/student_topic_progress', {'user_id': 'eq.${user.id}', 'select': '*'}),
      headers: _headers,
    );
    final Map<int, Map<String, dynamic>> progressMap = {};
    if (progressRes.statusCode == 200) {
      final prList = jsonDecode(progressRes.body) as List;
      for (final item in prList) {
        final progId = (item['progression_id'] as num).toInt();
        progressMap[progId] = item as Map<String, dynamic>;
      }
    }

    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1 = Mon, ..., 5 = Fri, 6 = Sat, 7 = Sun
    final todaySlot = todayWeekday <= 5 ? todayWeekday - 1 : 5;

    final allTopics = <OfficialProgression>[];
    final weeklyTopics = <OfficialProgression>[];
    final classSubjectsSet = <String>{};

    int understoodCount = 0;
    int needsRevisionCount = 0;

    final candidateTodayTopics = <OfficialProgression>[];

    for (final row in progList) {
      final pId = (row['id'] as num).toInt();
      final rawSubject = row['subject_name'] as String? ?? '';
      final pSubject = cleanSubjectName(rawSubject);
      if (pSubject.isEmpty) continue;

      // If student has chosen offered subjects, strictly filter out unoffered subjects!
      if (cleanOffered.isNotEmpty && !cleanOffered.contains(pSubject)) {
        continue;
      }
      classSubjectsSet.add(pSubject);

      final pDays = (row['study_days'] as String? ?? '').toLowerCase();
      final pStatus =
          progressMap[pId]?['status'] as String? ?? 'not_started';
      final pLevel =
          progressMap[pId]?['understanding_level'] as String? ?? 'none';

      if (pStatus == 'understood') understoodCount++;
      if (pStatus == 'needs_revision') needsRevisionCount++;

      final progObj = OfficialProgression(
        id: pId,
        subsystemId: (row['subsystem_id'] as num).toInt(),
        classId: classId,
        subjectName: pSubject,
        topicTitle: row['topic_title'] as String? ?? '',
        subtopics: row['subtopics'] as String?,
        weekNumber: (row['week_number'] as num?)?.toInt() ?? 1,
        startDate: row['start_date'] as String? ?? '',
        endDate: row['end_date'] as String? ?? '',
        studyDays: row['study_days'] as String?,
        studentStatus: pStatus,
        understandingLevel: pLevel,
      );

      allTopics.add(progObj);

      final slot = daySlotForProgression(pDays, pSubject);
      if (todaySlot == 5) {
        if (slot == 5 || pStatus == 'needs_revision') {
          candidateTodayTopics.add(progObj);
        }
      } else {
        if (slot == todaySlot) {
          candidateTodayTopics.add(progObj);
        }
      }
      weeklyTopics.add(progObj);
    }

    // Schedule at most 4 lessons for the day, with no duplicate lessons (highest 4 lessons/day)
    final sourceList = candidateTodayTopics.isNotEmpty
        ? candidateTodayTopics
        : (todaySlot == 5
            ? allTopics.where((t) => t.studentStatus == 'needs_revision').toList()
            : allTopics);

    final finalToday = <OfficialProgression>[];
    final seenTitles = <String>{};
    final seenSubjects = <String>{};

    // First pass: select distinct subjects for variety
    for (final prog in sourceList) {
      final normTitle = prog.topicTitle.toLowerCase().trim();
      final normSubj = prog.subjectName.toLowerCase().trim();
      if (seenTitles.contains(normTitle)) continue;
      if (!seenSubjects.contains(normSubj)) {
        finalToday.add(prog);
        seenTitles.add(normTitle);
        seenSubjects.add(normSubj);
        if (finalToday.length >= 4) break;
      }
    }

    // Second pass: fill up to 4 if needed without repeating any lesson
    if (finalToday.length < 4) {
      for (final prog in sourceList) {
        final normTitle = prog.topicTitle.toLowerCase().trim();
        if (seenTitles.contains(normTitle)) continue;
        finalToday.add(prog);
        seenTitles.add(normTitle);
        if (finalToday.length >= 4) break;
      }
    }

    return StudentHomeData(
      user: user,
      profile: profile,
      todayTopics: finalToday,
      weeklyTopics: weeklyTopics.take(15).toList(),
      allTopics: allTopics,
      classSubjects: classSubjectsSet.toList()..sort(),
      understoodCount: understoodCount,
      needsRevisionCount: needsRevisionCount,
      totalTopicsCount: allTopics.length,
    );
  }

  // --- UPDATE TOPIC PROGRESS ---
  Future<StudentHomeData> updateTopicProgress({
    required AppUser user,
    required int progressionId,
    required String status,
    required String understandingLevel,
    int? quizScore,
    String? weaknessNotes,
  }) async {
    final headersWithUpsert = Map<String, String>.from(_headers)
      ..['Prefer'] = 'resolution=merge-duplicates,return=representation';

    final body = {
      'user_id': user.id,
      'progression_id': progressionId,
      'status': status,
      'understanding_level': understandingLevel,
      if (quizScore != null) 'quiz_score': quizScore,
      if (weaknessNotes != null) 'weakness_notes': weaknessNotes,
      'last_studied_at': DateTime.now().toUtc().toIso8601String(),
    };

    await http.post(
      _restUri('/student_topic_progress', {'on_conflict': 'user_id,progression_id'}),
      headers: headersWithUpsert,
      body: jsonEncode(body),
    );

    return getStudentHome(user);
  }

  // --- AI TUTOR (Direct Gemini 3.1 Flash Lite API) ---
  Future<AiResponse> askTutor({
    required String prompt,
    String? context,
    String? className,
    String? studentName,
    String? preferredLearningStyle,
    String? languageCode,
  }) async {
    final isFr = languageCode == 'fr';
    final systemPrompt = isFr
        ? "Tu es Kivora AI, un enseignant camerounais bienveillant, clair et encourageant. Tu aides les élèves du sous-système anglophone et francophone (Cameroun) à maîtriser leur programme officiel. Réponds en français simple, pédagogique et structuré avec des exemples concrets du quotidien camerounais."
        : "You are Kivora AI, a warm, encouraging, and clear Cameroonian classroom teacher. You help students in Cameroon master their official curriculum. Explain clearly with concrete local everyday examples.";

    final userMessage = """
$systemPrompt

Contexte de l'élève :
Nom : ${studentName ?? 'Élève'}
Classe : ${className ?? 'Classe officielle'}
Style d'apprentissage : ${preferredLearningStyle ?? 'Exemples concrets'}
${context != null && context.isNotEmpty ? 'Sujet/Chapitre : $context' : ''}

Question de l'élève :
$prompt
""";

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey';
    final geminiRes = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': userMessage}
            ]
          }
        ]
      }),
    );

    if (geminiRes.statusCode != 200) {
      throw Exception('Erreur de réponse Kivora AI (${geminiRes.statusCode})');
    }

    final decoded = jsonDecode(geminiRes.body);
    final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String? ??
        'Pas de réponse.';

    return AiResponse(
      interactionType: 'chat',
      content: text,
      modelUsed: geminiModel,
    );
  }

  // --- AI QUIZ GENERATION ---
  Future<AiResponse> generateQuiz({
    required String topicTitle,
    String? subtopics,
    String? className,
    String? languageCode,
  }) async {
    final prompt = """
Génère un quiz officiel de 3 questions à choix multiples (QCM) pour évaluer la maîtrise du chapitre suivant :
Classe : ${className ?? 'Secondaire'}
Chapitre : $topicTitle
Sous-thèmes : ${subtopics ?? ''}

Retourne STRICTEMENT du code JSON valide au format exact suivant, sans texte avant ni après :
{
  "explanation": "Voici votre quiz officiel pour réviser $topicTitle.",
  "quiz": [
    {
      "question": "Texte de la question ?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "answer": "Option A",
      "explanation": "Explication claire de la bonne réponse."
    }
  ]
}
""";

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey';
    final geminiRes = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    if (geminiRes.statusCode == 200) {
      final decoded = jsonDecode(geminiRes.body);
      var raw = decoded['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String? ??
          '{}';
      raw = raw.replaceAll(RegExp(r'^```json\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return AiResponse.fromJson(parsed);
      } catch (_) {}
    }

    return AiResponse(
      interactionType: 'quiz',
      content: 'Quiz pour $topicTitle',
      modelUsed: geminiModel,
    );
  }

  // --- AI TOPIC SUMMARY ---
  Future<AiResponse> summarizeTopic({
    required String topicTitle,
    String? subtopics,
    String? className,
    String? languageCode,
  }) async {
    final isFr = languageCode == 'fr';
    final prompt = isFr
        ? "Fournis un résumé vérifié, clair et complet du cours camerounais : $topicTitle (Classe: ${className ?? ''}). Détaille les définitions essentielles, les formules ou règles clés, et un exemple type d'examen."
        : "Provide a verified, clear, and comprehensive summary of the Cameroon official curriculum topic: $topicTitle (Class: ${className ?? ''}). Include key definitions, formulas/rules, and a typical exam example.";

    return askTutor(
      prompt: prompt,
      context: topicTitle,
      className: className,
      languageCode: languageCode,
    );
  }

  // --- ADMIN DASHBOARD ---
  Future<AdminDashboardData> getAdminDashboard(AppUser admin) async {
    // 1. Count users
    final usersRes = await http.get(
      _restUri('/users', {'select': 'id,full_name,email,role,created_at'}),
      headers: _headers,
    );
    final usersList = usersRes.statusCode == 200
        ? (jsonDecode(usersRes.body) as List)
        : [];
    final students = usersList.where((u) => u['role'] == 'student').toList();

    return AdminDashboardData(
      admin: admin,
      subsystemsCount: 2,
      classesCount: 14,
      studentsCount: students.length,
      progressionsCount: 47140,
      programTopicsCount: 50998,
      recentStudents: students
          .take(10)
          .map((s) => s as Map<String, dynamic>)
          .toList(),
      progressions: const [],
      uploadedFolders: const [],
    );
  }

  // --- SUBJECTS OF A CLASS ---
  Future<List<String>> getClassSubjects(int classId) async {
    final res = await http.get(
      _restUri('/official_progressions',
          {'class_id': 'eq.$classId', 'select': 'subject_name', 'limit': '3000'}),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final set = <String>{};
    for (final r in jsonDecode(res.body) as List) {
      final raw = (r['subject_name'] as String? ?? '').trim();
      final cleaned = cleanSubjectName(raw);
      if (cleaned.length > 1) set.add(cleaned);
    }
    return set.toList()..sort();
  }

  // --- EXPLORE TOPICS ---
  Future<List<OfficialProgression>> exploreTopics({
    int? subsystemId,
    int? classId,
    String? subjectName,
    String? query,
    int limit = 50,
  }) async {
    final q = <String, dynamic>{
      'order': 'week_number.asc,id.asc',
      'limit': '$limit',
    };
    if (subsystemId != null) q['subsystem_id'] = 'eq.$subsystemId';
    if (classId != null) q['class_id'] = 'eq.$classId';
    if (subjectName != null && subjectName.isNotEmpty) {
      final clean = cleanSubjectName(subjectName);
      q['subject_name'] = 'ilike.*$clean*';
    }
    if (query != null && query.trim().isNotEmpty) {
      q['or'] =
          '(topic_title.ilike.*${query.trim()}*,subject_name.ilike.*${query.trim()}*,subtopics.ilike.*${query.trim()}*)';
    }
    final res = await http.get(_restUri('/official_progressions', q),
        headers: _headers);
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    final results = <OfficialProgression>[];
    final seen = <String>{};
    for (final e in list) {
      final title = (e['topic_title'] as String? ?? '').trim().toLowerCase();
      if (title.isNotEmpty && seen.contains(title)) continue;
      if (title.isNotEmpty) seen.add(title);
      results.add(
        OfficialProgression(
          id: (e['id'] as num).toInt(),
          subsystemId: (e['subsystem_id'] as num?)?.toInt() ?? 1,
          classId: (e['class_id'] as num?)?.toInt() ?? 1,
          subjectName: cleanSubjectName(e['subject_name'] as String? ?? ''),
          topicTitle: e['topic_title'] as String? ?? '',
          subtopics: e['subtopics'] as String?,
          weekNumber: (e['week_number'] as num?)?.toInt() ?? 1,
          startDate: e['start_date'] as String? ?? '',
          endDate: e['end_date'] as String? ?? '',
          studyDays: e['study_days'] as String?,
          studentStatus: 'not_started',
          understandingLevel: 'none',
        ),
      );
    }
    return results;
  }

  Future<bool> changePassword({
    required int userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final res = await http.get(
      _restUri('/users', {'id': 'eq.$userId', 'select': 'password_hash'}),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Erreur de vérification du compte.');
    }
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) throw Exception('Utilisateur introuvable.');
    final currentHash = list.first['password_hash'] as String? ?? '';
    if (!verifyPassword(oldPassword, currentHash)) {
      throw Exception('L\'ancien mot de passe est incorrect.');
    }
    if (newPassword.trim().length < 4) {
      throw Exception('Le nouveau mot de passe doit comporter au moins 4 caractères.');
    }
    final newHash = hashPassword(newPassword.trim());
    final patchRes = await http.patch(
      _restUri('/users', {'id': 'eq.$userId'}),
      headers: _headers,
      body: jsonEncode({'password_hash': newHash}),
    );
    return patchRes.statusCode >= 200 && patchRes.statusCode < 300;
  }

}
