import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/study_models.dart';
import '../providers/study_provider.dart';

class QuestionnaireScreen extends StatefulWidget {
  final StudentProfile? existingProfile;
  final bool isEditing;
  final int initialStep;

  const QuestionnaireScreen({
    super.key,
    this.existingProfile,
    this.isEditing = false,
    this.initialStep = 0,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  static const Color _plumPrimary = Color(0xFF26145E);
  static const int _totalQuestions = 7;

  static const List<String> _francophoneFallbackSubjects = [
    'Mathématiques',
    'Physique',
    'Chimie',
    'SVTEEHB',
    'Philosophie',
    'Français',
    'Anglais',
    'Histoire',
    'Géographie',
    'Informatique',
    'Économie',
    'Comptabilité',
  ];

  static const List<String> _anglophoneFallbackSubjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'Computer Science',
    'English Language',
    'French',
    'History',
    'Geography',
    'Economics',
  ];

  List<String> _classSubjects = List.from(_francophoneFallbackSubjects);
  bool _loadingSubjects = false;

  static const List<String> _difficultyReasons = [
    'Understanding formulas and rules',
    'Concentrating while studying',
    'Remembering what I studied',
    'Applying concepts to exercises',
    'Fast pace in class',
  ];

  static const List<String> _difficultyReasonsFr = [
    'Comprendre les formules et les règles',
    'Me concentrer pendant l\'étude',
    'Mémoriser ce que j\'ai étudié',
    'Appliquer les concepts aux exercices',
    'Rythme trop rapide en classe',
  ];

  static const List<String> _defaultHobbies = [
    'Football',
    'Music',
    'Reading',
    'Video games',
    'Movies',
    'Technology',
    'Drawing',
    'Dancing',
  ];

  int _step = 0;
  int? _subsystemId;
  int? _classId;
  int _age = 15;
  String _favouriteSubject = 'Mathématiques';
  final Set<String> _difficultSubjects = {'Physique'};
  String _difficultyReason = 'Comprendre les formules et les règles';
  final Set<String> _hobbies = {'Football'};
  String _activityStyle = 'both';
  String _learningStyle = 'visual_simulations';
  String _fallbackPreference = 'another_example';
  String _exercisePreference = 'short_quizzes';
  String _preferredStudyPeriod = 'evening';
  int _dailyGoalMinutes = 60;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 18, minute: 0);
  final _fullNameCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _customHobbyCtrl = TextEditingController();
  String? _error;

  Future<void> _fetchClassSubjects(int? classId) async {
    if (classId == null) return;
    setState(() => _loadingSubjects = true);
    try {
      final api = context.read<StudyProvider>().api;
      final subs = await api.getClassSubjects(classId);
      if (mounted && subs.isNotEmpty) {
        setState(() {
          _classSubjects = subs;
          if (!_classSubjects.contains(_favouriteSubject)) {
            _favouriteSubject = _classSubjects.first;
          }
          _difficultSubjects.retainAll(_classSubjects);
          if (_difficultSubjects.isEmpty && _classSubjects.length > 1) {
            _difficultSubjects.add(_classSubjects.length > 1 ? _classSubjects[1] : _classSubjects.first);
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load class subjects: $e');
    } finally {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, _totalQuestions - 1);
    _fullNameCtrl.text = context.read<StudyProvider>().user?.fullName ?? '';
    final existing = widget.existingProfile;
    if (existing != null) {
      _subsystemId = existing.subsystemId;
      _classId = existing.classId;
      _age = existing.age ?? 15;
      
      String mapSubj(String name) {
        if (_subsystemId == 2) {
          final low = name.trim().toLowerCase();
          if (low == 'mathematics' || low == 'maths' || low == 'math') return 'Mathématiques';
          if (low == 'physics') return 'Physique';
          if (low == 'chemistry') return 'Chimie';
          if (low == 'biology') return 'SVTEEHB';
          if (low == 'computer science') return 'Informatique';
          if (low == 'english language' || low == 'english') return 'Anglais';
          if (low == 'french') return 'Français';
          if (low == 'history') return 'Histoire';
          if (low == 'geography') return 'Géographie';
          if (low == 'economics') return 'Économie';
          if (low == 'accounting') return 'Comptabilité';
        }
        return name;
      }
      
      _favouriteSubject = mapSubj(existing.favouriteSubject ?? (_subsystemId == 2 ? 'Mathématiques' : 'Mathematics'));
      _difficultSubjects
        ..clear()
        ..addAll(existing.difficultSubjects.map(mapSubj));
      if (existing.difficultyReason != null &&
          existing.difficultyReason!.isNotEmpty) {
        _difficultyReason = existing.difficultyReason!;
      }
      if (existing.hobbies.isNotEmpty) {
        _hobbies
          ..clear()
          ..addAll(existing.hobbies);
      }
      _activityStyle = existing.activityStyle;
      _learningStyle = existing.learningStyle;
      _fallbackPreference = existing.fallbackPreference;
      _exercisePreference = existing.exercisePreference;
      _preferredStudyPeriod = existing.preferredStudyPeriod;
      _dailyGoalMinutes = existing.dailyGoalMinutes;
      _goalCtrl.text = existing.academicGoal ?? '';
      _reminderTime = TimeOfDay(
        hour: existing.reminderHour,
        minute: existing.reminderMinute,
      );
    }
    final homeSubjects = context.read<StudyProvider>().studentHome?.classSubjects;
    if (homeSubjects != null && homeSubjects.isNotEmpty) {
      _classSubjects = List.from(homeSubjects);
    } else if (_subsystemId == 2) {
      _classSubjects = List.from(_francophoneFallbackSubjects);
    } else if (_subsystemId == 1) {
      _classSubjects = List.from(_anglophoneFallbackSubjects);
    }
    if (_classSubjects.isNotEmpty) {
      if (!_classSubjects.contains(_favouriteSubject)) {
        _favouriteSubject = _classSubjects.first;
      }
      _difficultSubjects.retainAll(_classSubjects);
      if (_difficultSubjects.isEmpty && _classSubjects.length > 1) {
        _difficultSubjects.add(_classSubjects[1]);
      }
    }
    if (_classId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchClassSubjects(_classId);
      });
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _goalCtrl.dispose();
    _customHobbyCtrl.dispose();
    super.dispose();
  }

  void _addCustomHobby() {
    final hobby = _customHobbyCtrl.text.trim();
    if (hobby.isEmpty) return;
    setState(() {
      _hobbies.add(hobby);
      _customHobbyCtrl.clear();
    });
  }

  Future<void> _submit(StudyProvider provider) async {
    if (_subsystemId == null || _classId == null) {
      setState(() => _error = 'Please choose your subsystem and class.');
      return;
    }
    setState(() => _error = null);
    try {
      await provider.submitQuestionnaire(
        fullName: _fullNameCtrl.text.trim().isEmpty
            ? null
            : _fullNameCtrl.text.trim(),
        subsystemId: _subsystemId!,
        classId: _classId!,
        age: _age,
        favouriteSubject: _favouriteSubject,
        difficultSubjects: _difficultSubjects.toList(),
        difficultyReason: _difficultyReason,
        hobbies: _hobbies.toList(),
        activityStyle: _activityStyle,
        learningStyle: _learningStyle,
        fallbackPreference: _fallbackPreference,
        exercisePreference: _exercisePreference,
        preferredStudyPeriod: _preferredStudyPeriod,
        academicGoal:
            _goalCtrl.text.trim().isEmpty ? null : _goalCtrl.text.trim(),
        dailyGoalMinutes: _dailyGoalMinutes,
        reminderHour: _reminderTime.hour,
        reminderMinute: _reminderTime.minute,
      );
      if (mounted && widget.isEditing) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final isFr = provider.languageCode == 'fr' || _subsystemId == 2;
    final subsystems = provider.subsystems;

    if (_subsystemId == null && subsystems.isNotEmpty) {
      _subsystemId = subsystems.first.id;
    }
    final selectedSub =
        subsystems.where((s) => s.id == _subsystemId).firstOrNull;
    final classes = selectedSub?.classes ?? [];
    if ((_classId == null || !classes.any((c) => c.id == _classId)) &&
        classes.isNotEmpty) {
      _classId = classes.first.id;
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFAF9FE),
                  Color(0xFFF3EFFB),
                  Color(0xFFEDE7F8),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 490),
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE7E1F5)),
                      boxShadow: [
                        BoxShadow(
                          color: _plumPrimary.withAlpha(18),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isEditing
                                      ? (isFr ? 'Modifier le profil' : 'Update Profile')
                                      : 'Questionnaire',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E105A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isFr
                                      ? 'Question ${_step + 1} sur $_totalQuestions'
                                      : '${_step + 1} out of $_totalQuestions questions',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: widget.isEditing
                                  ? () => Navigator.pop(context)
                                  : provider.logout,
                              child: Text(
                                widget.isEditing ? (isFr ? 'Annuler' : 'Cancel') : (isFr ? 'Déconnexion' : 'Sign Out'),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.isEditing) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: List.generate(_totalQuestions, (i) {
                              final labels = isFr
                                  ? [
                                      '1. Profil',
                                      '2. Classe',
                                      '3. Âge',
                                      '4. Matières',
                                      '5. Loisirs',
                                      '6. Style',
                                      '7. Planning',
                                    ]
                                  : [
                                      '1. Profile',
                                      '2. Class',
                                      '3. Age',
                                      '4. Subjects',
                                      '5. Interests',
                                      '6. Style',
                                      '7. Schedule',
                                    ];
                              final active = _step == i;
                              return ChoiceChip(
                                label: Text(
                                  labels[i],
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                selected: active,
                                onSelected: (_) => setState(() => _step = i),
                                visualDensity: VisualDensity.compact,
                              );
                            }),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _buildQuestionBody(subsystems, classes, isFr),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 8,
                          runSpacing: 10,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_step > 0)
                              TextButton.icon(
                                onPressed: () => setState(() => _step--),
                                icon: const Icon(Icons.arrow_back, size: 16),
                                label: Text(
                                  isFr ? 'Retour' : 'Back',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 1),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (widget.isEditing && _step < _totalQuestions - 1)
                                  OutlinedButton(
                                    onPressed: provider.isLoading ? null : () => _submit(provider),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(isFr ? 'Enregistrer' : 'Save'),
                                  ),
                                FilledButton(
                                  onPressed: provider.isLoading
                                      ? null
                                      : () {
                                          if (_step < _totalQuestions - 1) {
                                            setState(() => _step++);
                                          } else {
                                            _submit(provider);
                                          }
                                        },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _plumPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: provider.isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(
                                          _step < _totalQuestions - 1
                                              ? (isFr ? 'Suivant' : 'Next')
                                              : (widget.isEditing
                                                  ? (isFr ? 'Enregistrer' : 'Save changes')
                                                  : (isFr ? 'Terminer' : 'Finish')),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBody(
    List<Subsystem> subsystems,
    List<SchoolClass> classes,
    bool isFr,
  ) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isEditing) ...[
              const Text(
                'Full Name',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fullNameCtrl,
                decoration: InputDecoration(
                  hintText: 'Your full name',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Which educational subsystem do you follow?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 14),
            ...subsystems.map((sub) {
              final selected = sub.id == _subsystemId;
              return _RadioOptionCard(
                title: sub.name,
                subtitle: sub.code == 'en'
                    ? 'Form 1 to Upper Sixth'
                    : '6ème to Terminale',
                selected: selected,
                onTap: () {
                  setState(() {
                    _subsystemId = sub.id;
                    _classId =
                        sub.classes.isNotEmpty ? sub.classes.first.id : null;
                    if (sub.id == 2) {
                      _classSubjects = List.from(_francophoneFallbackSubjects);
                    } else {
                      _classSubjects = List.from(_anglophoneFallbackSubjects);
                    }
                    _favouriteSubject = _classSubjects.first;
                    _difficultSubjects.clear();
                    if (_classSubjects.length > 1) _difficultSubjects.add(_classSubjects[1]);
                  });
                  if (_classId != null) {
                    _fetchClassSubjects(_classId);
                  }
                },
              );
            }),
          ],
        );

      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Which class are you in?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This lets Kivora load your official weekly study programme.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _classId,
              decoration: _dropdownDecoration('Select your class'),
              items: classes
                  .map(
                    (c) => DropdownMenuItem<int>(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() => _classId = val);
                if (val != null) {
                  _fetchClassSubjects(val);
                }
              },
            ),
          ],
        );

      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How old are you?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Helps the AI adjust explanations and examples to your level.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _age,
              decoration: _dropdownDecoration('Select your age'),
              items: List.generate(16, (i) => i + 10)
                  .map(
                    (age) => DropdownMenuItem<int>(
                      value: age,
                      child: Text('$age years old', overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _age = val);
              },
            ),
          ],
        );

      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFr
                  ? 'Vos matières fortes et vos défis'
                  : 'Your subject strengths & challenges',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isFr
                  ? 'Matières enseignées dans votre classe'
                  : (_classSubjects.isNotEmpty
                      ? 'Subjects taught in your selected class'
                      : 'Select your subject preferences'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            if (_loadingSubjects)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(
                      isFr ? 'Chargement des matières...' : 'Loading class subjects...',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _classSubjects.contains(_favouriteSubject)
                  ? _favouriteSubject
                  : (_classSubjects.isNotEmpty ? _classSubjects.first : null),
              decoration: _dropdownDecoration(
                isFr ? 'Matière que vous préférez' : 'Subject you enjoy the most',
              ),
              items: _classSubjects
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _favouriteSubject = val);
              },
            ),
            const SizedBox(height: 16),
            Text(
              isFr
                  ? 'Quelles matières trouvez-vous difficiles ?'
                  : 'Which subjects do you find difficult?',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _classSubjects.map((subj) {
                final selected = _difficultSubjects.contains(subj);
                return FilterChip(
                  label: Text(subj),
                  selected: selected,
                  selectedColor: _plumPrimary.withAlpha(30),
                  checkmarkColor: _plumPrimary,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? _plumPrimary : const Color(0xFF334155),
                  ),
                  onSelected: (val) => setState(() {
                    if (val) {
                      _difficultSubjects.add(subj);
                    } else {
                      _difficultSubjects.remove(subj);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(
              isFr
                  ? 'Qu\'est-ce qui rend une matière difficile pour vous ?'
                  : 'What usually makes a subject difficult for you?',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            ...(isFr ? _difficultyReasonsFr : _difficultyReasons).map(
              (reason) => _RadioOptionCard(
                title: reason,
                selected: _difficultyReason == reason,
                onTap: () => setState(() => _difficultyReason = reason),
              ),
            ),
          ],
        );

      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What do you enjoy in your free time?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Kivora uses your interests (like football or music) to build relatable examples.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: {..._defaultHobbies, ..._hobbies}.map((hobby) {
                final selected = _hobbies.contains(hobby);
                return FilterChip(
                  label: Text(hobby),
                  selected: selected,
                  onSelected: (val) => setState(() {
                    if (val) {
                      _hobbies.add(hobby);
                    } else {
                      _hobbies.remove(hobby);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customHobbyCtrl,
                    decoration: _dropdownDecoration('Add another interest...'),
                    onSubmitted: (_) => _addCustomHobby(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _addCustomHobby,
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Do you prefer individual or group activities?',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            _RadioOptionCard(
              title: 'Individual activities',
              selected: _activityStyle == 'individual',
              onTap: () => setState(() => _activityStyle = 'individual'),
            ),
            _RadioOptionCard(
              title: 'Group activities',
              selected: _activityStyle == 'group',
              onTap: () => setState(() => _activityStyle = 'group'),
            ),
            _RadioOptionCard(
              title: 'Both',
              selected: _activityStyle == 'both',
              onTap: () => setState(() => _activityStyle = 'both'),
            ),
          ],
        );

      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How do you prefer to learn?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _RadioOptionCard(
              title: 'Through interactive simulations & visuals',
              selected: _learningStyle == 'visual_simulations',
              onTap: () =>
                  setState(() => _learningStyle = 'visual_simulations'),
            ),
            _RadioOptionCard(
              title: 'Through practical real-life examples',
              selected: _learningStyle == 'practical_examples',
              onTap: () =>
                  setState(() => _learningStyle = 'practical_examples'),
            ),
            _RadioOptionCard(
              title: 'Through clear step-by-step written explanations',
              selected: _learningStyle == 'step_by_step',
              onTap: () => setState(() => _learningStyle = 'step_by_step'),
            ),
            _RadioOptionCard(
              title: 'Through short videos & animations',
              selected: _learningStyle == 'videos_animations',
              onTap: () =>
                  setState(() => _learningStyle = 'videos_animations'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _fallbackPreference,
              decoration: _dropdownDecoration(
                "When you don't understand, what helps most?",
              ),
              items: const [
                DropdownMenuItem(
                  value: 'another_example',
                  child: Text('Seeing another example', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(
                  value: 'simpler_explanation',
                  child: Text('Simpler step-by-step explanation', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(
                  value: 'visual_demonstration',
                  child: Text('Watching a visual demonstration', overflow: TextOverflow.ellipsis),
                ),
                DropdownMenuItem(
                  value: 'guided_exercises',
                  child: Text('Solving exercises with guidance', overflow: TextOverflow.ellipsis),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _fallbackPreference = v);
              },
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Study habits & your academic goal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _preferredStudyPeriod,
              decoration:
                  _dropdownDecoration('When do you prefer to study?'),
              items: const [
                DropdownMenuItem(value: 'morning', child: Text('Morning')),
                DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                DropdownMenuItem(value: 'evening', child: Text('Evening')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _preferredStudyPeriod = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: [30, 45, 60, 90, 120].contains(_dailyGoalMinutes)
                  ? _dailyGoalMinutes
                  : 60,
              decoration: _dropdownDecoration('Daily study time'),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 minutes / day')),
                DropdownMenuItem(value: 45, child: Text('45 minutes / day')),
                DropdownMenuItem(value: 60, child: Text('1 hour / day')),
                DropdownMenuItem(value: 90, child: Text('1.5 hours / day')),
                DropdownMenuItem(value: 120, child: Text('2 hours / day')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _dailyGoalMinutes = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goalCtrl,
              decoration: _dropdownDecoration(
                'Your goal (e.g. Pass GCE / BEPC / Improve grades)',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.notifications_active_outlined,
                color: _plumPrimary,
              ),
              title: const Text(
                'Daily study reminder',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Sunday weekly overview + daily at ${_reminderTime.format(context)}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _reminderTime,
                );
                if (picked != null) {
                  setState(() => _reminderTime = picked);
                }
              },
            ),
          ],
        );
    }
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, overflow: TextOverflow.ellipsis),
      filled: true,
      fillColor: const Color(0xFFF7F7FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _plumPrimary, width: 1.5),
      ),
    );
  }
}

class _RadioOptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RadioOptionCard({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF26145E);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF4F1FC) : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? primary : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
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
  }
}
