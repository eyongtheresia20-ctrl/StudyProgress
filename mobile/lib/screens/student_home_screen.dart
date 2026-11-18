import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/study_models.dart';
import '../providers/study_provider.dart';
import '../widgets/app_logo.dart';
import 'ai_tutor_screen.dart';
import 'notifications_screen.dart';
import 'questionnaire_screen.dart';

String _formatStudentFirstName(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return 'Student';
  final first = clean.split(RegExp(r'\s+')).first;
  if (first.isEmpty) return 'Student';
  return first[0].toUpperCase() + first.substring(1).toLowerCase();
}

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  static const Color _primaryBlue = Color(0xFF2563EB);

  int _tabIndex = 0;
  int? _aiProgressionId;
  String? _aiSubjectName;
  String? _aiTopicTitle;

  void _openAiTutor(
    int? progressionId,
    AppStrings s, {
    String? subjectName,
    String? topicTitle,
  }) {
    setState(() {
      _aiProgressionId = progressionId;
      _aiSubjectName = subjectName;
      _aiTopicTitle = topicTitle;
      _tabIndex = 3;
    });
  }

  void _openEditQuestionnaire(StudentProfile? profile, {int initialStep = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionnaireScreen(
          existingProfile: profile,
          isEditing: true,
          initialStep: initialStep,
        ),
      ),
    );
  }

  void _openNotificationsScreen(AppStrings s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          onOpenTab: (tab) => setState(() => _tabIndex = tab),
          onOpenAiTopic: (id) => _openAiTutor(id, s),
        ),
      ),
    );
  }

  String _formattedToday(AppStrings s) {
    final now = DateTime.now();
    const weekdaysEn = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const weekdaysFr = [
      'LUNDI',
      'MARDI',
      'MERCREDI',
      'JEUDI',
      'VENDREDI',
      'SAMEDI',
      'DIMANCHE',
    ];
    const monthsEn = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    const monthsFr = [
      'JANVIER',
      'FÉVRIER',
      'MARS',
      'AVRIL',
      'MAI',
      'JUIN',
      'JUILLET',
      'AOÛT',
      'SEPTEMBRE',
      'OCTOBRE',
      'NOVEMBRE',
      'DÉCEMBRE',
    ];
    final wd = s.isFr
        ? weekdaysFr[now.weekday - 1]
        : weekdaysEn[now.weekday - 1];
    final mo =
        s.isFr ? monthsFr[now.month - 1] : monthsEn[now.month - 1];
    return '$wd, ${now.day} $mo';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final home = provider.studentHome;
    final s = AppStrings(provider.languageCode);

    final userName = home?.user.fullName ?? provider.user?.fullName ?? 'Student';
    final initial =
        userName.trim().isNotEmpty ? userName.trim()[0].toUpperCase() : 'K';

    final pages = [
      _HomeDashboardTab(
        home: home,
        userName: userName,
        dateLabel: _formattedToday(s),
        s: s,
        onStudyWithAi: (id) => _openAiTutor(id, s),
        onOpenProgram: () => setState(() => _tabIndex = 1),
      ),
      _MyProgrammeTab(
        home: home,
        dateLabel: _formattedToday(s),
        s: s,
        onStudyWithAi: (id) => _openAiTutor(id, s),
      ),
      _ExploreTab(
        home: home,
        s: s,
        onSelectOfficialTopic: (id) => _openAiTutor(id, s),
        onSelectCustomTopic: (subject, topic) => _openAiTutor(
          null,
          s,
          subjectName: subject,
          topicTitle: topic,
        ),
      ),
      AiTutorScreen(
        initialProgressionId: _aiProgressionId,
        initialSubjectName: _aiSubjectName,
        initialTopicTitle: _aiTopicTitle,
        onBack: () => setState(() => _tabIndex = 0),
      ),
      _ProgressJourneyTab(
        home: home,
        s: s,
        onReviseWithAi: (id) => _openAiTutor(id, s),
      ),
      _ProfileTab(
        home: home,
        userName: userName,
        initial: initial,
        s: s,
        onEditQuestionnaire: ([step = 0]) =>
            _openEditQuestionnaire(home?.profile, initialStep: step),
      ),
    ];

    final unreadCount =
        (home?.todayTopics.length ?? 0) + (home?.needsRevisionCount ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.4,
        titleSpacing: 16,
        title: const Row(
          children: [
            KivoraLogo(size: 32),
            SizedBox(width: 10),
            Text(
              'Kivora',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          _LanguageTogglePill(
            currentLang: provider.languageCode,
            onChanged: provider.setLanguage,
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: s.notifications,
            onPressed: () => _openNotificationsScreen(s),
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 2),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'profile') {
                  setState(() => _tabIndex = 5);
                } else if (value == 'logout') {
                  provider.logout();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'profile', child: Text(s.navProfile)),
                PopupMenuItem(value: 'logout', child: Text(s.signOut)),
              ],
              child: CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: Color(0xFF0F172A),
              );
            }
            return const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: Color(0xFF334155),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(size: 24, color: _primaryBlue);
            }
            return const IconThemeData(size: 24, color: Color(0xFF334155));
          }),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          indicatorColor: const Color(0xFFDBEAFE),
          selectedIndex: _tabIndex,
          onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
          destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home, color: _primaryBlue),
            label: s.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_today_outlined),
            selectedIcon: const Icon(Icons.calendar_today, color: _primaryBlue),
            label: s.navProgram,
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore, color: _primaryBlue),
            label: s.navExplore,
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
            label: 'AI',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart, color: _primaryBlue),
            label: s.navProgress,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person, color: _primaryBlue),
            label: s.navProfile,
          ),
        ],
      ),
    ),
    );
  }
}

class _LanguageTogglePill extends StatelessWidget {
  final String currentLang;
  final void Function(String code) onChanged;

  const _LanguageTogglePill({
    required this.currentLang,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF13346B);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['en', 'fr'].map((code) {
          final active = currentLang == code;
          return GestureDetector(
            onTap: () => onChanged(code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: active ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : primary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HomeDashboardTab extends StatelessWidget {
  final StudentHomeData? home;
  final String userName;
  final String dateLabel;
  final AppStrings s;
  final void Function(int? progressionId) onStudyWithAi;
  final VoidCallback onOpenProgram;

  const _HomeDashboardTab({
    required this.home,
    required this.userName,
    required this.dateLabel,
    required this.s,
    required this.onStudyWithAi,
    required this.onOpenProgram,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();

    if (home == null && provider.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: provider.refreshDashboard,
                child: Text(s.refresh),
              ),
            ],
          ),
        ),
      );
    }

    final data = home;
    final todayTopics = (data?.todayTopics.isNotEmpty == true)
        ? data!.todayTopics
        : (data?.weeklyTopics ?? []);
    final continueTopic = (data?.allTopics.isNotEmpty == true)
        ? data!.allTopics.firstWhere(
            (t) => t.studentStatus == 'in_progress',
            orElse: () => data.allTopics.first,
          )
        : null;

    return RefreshIndicator(
      onRefresh: provider.refreshDashboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Text(
            dateLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.welcomeStudent(_formatStudentFirstName(userName)),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.readyToProgress,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 18),

          // Deep Navy TODAY'S PROGRAMME Hero Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF13346B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.todaysProgrammeBadge,
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Colors.white70,
                      size: 19,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  s.yourLearningPlan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.scheduledCountText(todayTopics.length),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 14),
                if (todayTopics.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.noTopicTodayHint,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onOpenProgram,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF1F5F9),
                              foregroundColor: const Color(0xFF0F172A),
                            ),
                            child: Text('${s.fullProgramme}  →'),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ...todayTopics.take(3).map(
                        (topic) => Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      topic.subjectName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF334155),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      s.upcoming,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                topic.topicTitle,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF13346B),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${topic.subtopics ?? topic.studyDays ?? ""} • ${topic.studyDays ?? topic.startDate}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () => onStudyWithAi(topic.id),
                                  style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: Text(
                                    '${s.startLesson}  →',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (todayTopics.length > 3)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onOpenProgram,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          '${s.seeAll} (${todayTopics.length}) →',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Continue Learning section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.continueLearning,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              TextButton(
                onPressed: onOpenProgram,
                child: Text(
                  s.seeAll,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (continueTopic != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.calculate_outlined,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              continueTopic.topicTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${continueTopic.subjectName} • ${s.weekLabel(continueTopic.weekNumber)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => onStudyWithAi(continueTopic.id),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFDBEAFE),
                          foregroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                        ),
                        child: Text(
                          s.continueBtn,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: continueTopic.studentStatus == 'understood'
                          ? 1.0
                          : 0.55,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Your learning at a glance
          Text(
            s.learningAtGlance,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GlanceStatCard(
                  icon: Icons.menu_book_outlined,
                  iconColor: const Color(0xFF2563EB),
                  value: '${data?.understoodCount ?? 0}',
                  label: s.topicsStudied,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _GlanceStatCard(
                  icon: Icons.track_changes_outlined,
                  iconColor: const Color(0xFF10B981),
                  value: '${data?.understoodCount ?? 0}',
                  label: s.topicsUnderstood,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // AI Tutor shortcut card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFF7C3AED),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.needHelpTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.needHelpSub,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onStudyWithAi(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      s.talkToAi,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlanceStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _GlanceStatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyProgrammeTab extends StatefulWidget {
  final StudentHomeData? home;
  final String dateLabel;
  final AppStrings s;
  final void Function(int progressionId) onStudyWithAi;

  const _MyProgrammeTab({
    required this.home,
    required this.dateLabel,
    required this.s,
    required this.onStudyWithAi,
  });

  @override
  State<_MyProgrammeTab> createState() => _MyProgrammeTabState();
}

class _MyProgrammeTabState extends State<_MyProgrammeTab> {
  int _filterIndex = 0; // 0 = Daily, 1 = Weekly
  String? _selectedSubject;
  int? _selectedWeekday; // null = all week, 0 = Lundi, 1 = Mardi, 2 = Mercredi, 3 = Jeudi, 4 = Vendredi, 5 = Weekend Revision

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final home = widget.home;
    final profile = home?.profile;
    var rawList = _filterIndex == 0
        ? (home?.todayTopics ?? [])
        : (home?.weeklyTopics ?? []);

    if (_filterIndex == 1 && _selectedWeekday != null) {
      if (_selectedWeekday == 5) {
        // Weekend Revision
        final rev = rawList.where((t) {
          final d = (t.studyDays ?? '').toLowerCase();
          return d.contains('samedi') || d.contains('saturday') || d.contains('révision') || d.contains('revision');
        }).toList();
        rawList = rev.isNotEmpty ? rev : rawList;
      } else {
        const dayKeys = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi'];
        final key = dayKeys[_selectedWeekday!];
        rawList = rawList.where((t) => (t.studyDays ?? '').toLowerCase().contains(key)).toList();
      }
    }

    final subjects = <String>{
      for (final t in rawList)
        if (t.subjectName.isNotEmpty) t.subjectName,
    }.toList()
      ..sort();

    final list = _selectedSubject == null
        ? rawList
        : rawList.where((t) => t.subjectName == _selectedSubject).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.myProgramme,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${profile?.className ?? ""} • ${profile?.subsystemName ?? ""}',
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(s.tabDaily),
                    selected: _filterIndex == 0,
                    onSelected: (_) => setState(() {
                      _filterIndex = 0;
                      _selectedSubject = null;
                    }),
                  ),
                  ChoiceChip(
                    label: Text(s.tabWeekly),
                    selected: _filterIndex == 1,
                    onSelected: (_) => setState(() {
                      _filterIndex = 1;
                      _selectedSubject = null;
                    }),
                  ),
                ],
              ),
              if (_filterIndex == 1) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Toute la semaine' : 'All Week'),
                          selected: _selectedWeekday == null,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = null;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Lundi' : 'Monday'),
                          selected: _selectedWeekday == 0,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 0;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Mardi' : 'Tuesday'),
                          selected: _selectedWeekday == 1,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 1;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Mercredi' : 'Wednesday'),
                          selected: _selectedWeekday == 2,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 2;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Jeudi' : 'Thursday'),
                          selected: _selectedWeekday == 3,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 3;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Vendredi' : 'Friday'),
                          selected: _selectedWeekday == 4,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 4;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFD97706)),
                          label: Text(s.isFr ? 'Sam - Dim (Révision)' : 'Sat - Sun (Revision)'),
                          selected: _selectedWeekday == 5,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 5;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (subjects.length > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Toutes (${rawList.length})' : 'All (${rawList.length})'),
                          selected: _selectedSubject == null,
                          onSelected: (_) =>
                              setState(() => _selectedSubject = null),
                        ),
                      ),
                      ...subjects.map(
                        (subj) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              subj,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _selectedSubject == subj,
                            onSelected: (_) =>
                                setState(() => _selectedSubject = subj),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(s.noProgramTopics),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  itemCount: list.length,
                  itemBuilder: (_, idx) {
                    final topic = list[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${topic.subjectName} • ${s.weekLabel(topic.weekNumber)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  s.scheduled,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (topic.studyDays != null && topic.studyDays!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.event_note_rounded, size: 13, color: Color(0xFF1D4ED8)),
                                  const SizedBox(width: 6),
                                  Text(
                                    s.isFr
                                        ? (topic.studyDays!.contains('·') ? topic.studyDays!.split('·').first.trim() : topic.studyDays!)
                                        : (topic.studyDays!.contains('·') ? topic.studyDays!.split('·').last.trim() : topic.studyDays!),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E40AF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            topic.topicTitle,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (topic.subtopics != null &&
                              topic.subtopics!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              topic.subtopics!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            '${topic.startDate} → ${topic.endDate}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (topic.studentStatus == 'understood')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    s.isFr ? 'Maîtrisé ✓' : 'Understood ✓',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: () {
                                    context
                                        .read<StudyProvider>()
                                        .updateTopicProgress(
                                          progressionId: topic.id,
                                          status: 'understood',
                                          understandingLevel: 'full',
                                        );
                                  },
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                  ),
                                  label: Text(
                                    s.isFr ? 'Terminé' : 'Complete',
                                  ),
                                ),
                              FilledButton.tonal(
                                onPressed: () => widget.onStudyWithAi(topic.id),
                                child: Text(s.studyWithAi),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ExploreTab extends StatefulWidget {
  final StudentHomeData? home;
  final AppStrings s;
  final void Function(int progressionId) onSelectOfficialTopic;
  final void Function(String subjectName, String topicTitle)
      onSelectCustomTopic;

  const _ExploreTab({
    required this.home,
    required this.s,
    required this.onSelectOfficialTopic,
    required this.onSelectCustomTopic,
  });

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  final _searchCtrl = TextEditingController();
  List<OfficialProgression> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchTopics(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final list = await context.read<StudyProvider>().api.exploreTopics(
            query: q,
          );
      if (mounted) setState(() => _results = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _topicHintForSubject(String subject, bool isFr) {
    final low = subject.toLowerCase();
    if (low.contains('bio')) {
      return isFr
          ? 'Ex: Osmose, Division cellulaire, Respiration...'
          : 'e.g. Osmosis, Cell Division, Photosynthesis...';
    }
    if (low.contains('chem') || low.contains('chim')) {
      return isFr
          ? 'Ex: Réactions acido-basiques, Mole, Électrolyse...'
          : 'e.g. Acids & Bases, Mole Concept, Electrolysis...';
    }
    if (low.contains('phys')) {
      return isFr
          ? 'Ex: Lois de Newton, Circuits électriques, Optique...'
          : 'e.g. Newton Laws, Circuits, Optics...';
    }
    if (low.contains('econ') || low.contains('comm')) {
      return isFr
          ? 'Ex: Offre et demande, Entreprises, Inflation...'
          : 'e.g. Demand & Supply, Business Units, Inflation...';
    }
    if (low.contains('comp') || low.contains('info')) {
      return isFr
          ? 'Ex: Algorithmes, Bases de données, Réseaux...'
          : 'e.g. Algorithms, Databases, Logic Gates...';
    }
    return isFr
        ? 'Ex: Équations, Résumé de chapitre, Exercice...'
        : 'e.g. Key concepts, Worked examples, Revision...';
  }

  Future<void> _openSubjectPicker(String subject) async {
    final provider = context.read<StudyProvider>();
    final customTopicCtrl = TextEditingController();
    final filterCtrl = TextEditingController();
    List<OfficialProgression> subjectTopics = [];
    try {
      subjectTopics = await provider.api.exploreTopics(subject: subject);
    } catch (_) {
      subjectTopics = (provider.studentHome?.allTopics ?? [])
          .where((t) => t.subjectName.toLowerCase() == subject.toLowerCase())
          .toList();
    }

    if (!mounted) return;
    final className = provider.studentHome?.profile.className ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final q = filterCtrl.text.trim().toLowerCase();
          final filteredTopics = q.isEmpty
              ? subjectTopics
              : subjectTopics
                  .where(
                    (t) =>
                        t.topicTitle.toLowerCase().contains(q) ||
                        (t.subtopics ?? '').toLowerCase().contains(q),
                  )
                  .toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.90,
            minChildSize: 0.65,
            maxChildSize: 0.96,
            expand: false,
            builder: (_, scrollController) => Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFEFF6FF),
                        child: Icon(
                          _iconForSubject(subject),
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF13346B),
                              ),
                            ),
                            Text(
                              '${className.isNotEmpty ? "$className • " : ""}${subjectTopics.length} ${widget.s.isFr ? "leçons" : "topics"}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.s.isFr
                        ? 'Choisissez un sujet du programme ou saisissez n’importe quel thème :'
                        : 'Choose a topic from your class programme or type any topic you want to study:',
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customTopicCtrl,
                          decoration: InputDecoration(
                            hintText: _topicHintForSubject(subject, widget.s.isFr),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final topic = customTopicCtrl.text.trim();
                          if (topic.isEmpty) return;
                          Navigator.pop(ctx);
                          widget.onSelectCustomTopic(subject, topic);
                        },
                        child: Text(widget.s.studyWithAi),
                      ),
                    ],
                  ),
                  if (subjectTopics.length > 5) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: filterCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        hintText: widget.s.isFr
                            ? 'Filtrer les chapitres de $subject...'
                            : 'Filter $subject chapters & lessons...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredTopics.isEmpty
                        ? Center(
                            child: Text(
                              widget.s.isFr
                                  ? 'Aucune leçon correspondante pour le moment.'
                                  : 'No matching lessons found yet — type a topic above to study with AI.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF334155)),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: filteredTopics.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final t = filteredTopics[i];
                              return Material(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'W${t.weekNumber}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    t.topicTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  subtitle: Text(
                                    t.subtopics != null &&
                                            t.subtopics!.isNotEmpty
                                        ? t.subtopics!
                                        : '${t.className ?? ""} • ${widget.s.weekLabel(t.weekNumber)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: Color(0xFF2563EB),
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    final isOfficialProg =
                                        (provider.studentHome?.allTopics ?? [])
                                            .any(
                                      (op) =>
                                          op.id == t.id &&
                                          op.subjectName.toLowerCase() ==
                                              t.subjectName.toLowerCase(),
                                    );
                                    if (isOfficialProg) {
                                      widget.onSelectOfficialTopic(t.id);
                                    } else {
                                      widget.onSelectCustomTopic(
                                        t.subjectName,
                                        t.topicTitle,
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconForSubject(String subject) {
    final low = subject.toLowerCase();
    if (low.contains('math')) return Icons.calculate_outlined;
    if (low.contains('phys')) return Icons.science_outlined;
    if (low.contains('chem') || low.contains('chim')) {
      return Icons.biotech_outlined;
    }
    if (low.contains('bio') || low.contains('geo')) return Icons.eco_outlined;
    if (low.contains('comp') || low.contains('info') || low.contains('digit')) {
      return Icons.computer_outlined;
    }
    if (low.contains('econ') || low.contains('comm') || low.contains('bus')) {
      return Icons.trending_up_outlined;
    }
    if (low.contains('fr') || low.contains('engl')) {
      return Icons.translate_outlined;
    }
    return Icons.menu_book_outlined;
  }

  static String _cleanSubjectDisplayName(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(
      RegExp(r'^(?:[A-Z]{1,4}|classe(?:\s+de(?:\s+[^\-]+)?)?|form\s+\d+|lower\s+sixth|upper\s+sixth)\s*[-–:]\s*', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'^(?:all|tous|tout)\s*[-–:]\s*', caseSensitive: false), '');
    s = s.replaceAll('\ufffd', 'e');
    if (s.contains(' - ')) {
      final parts = s.split(' - ');
      if (parts[0].trim().split(' ').length <= 4 && parts[0].trim().length <= 32) {
        s = parts[0];
      }
    }
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final classSubjects = widget.home?.classSubjects ?? [];
    final cleanSubjects = classSubjects
        .map((name) => _cleanSubjectDisplayName(name))
        .where((subj) =>
            subj.length > 2 &&
            !RegExp(r'^(?:[A-Z]{1,3}|classe|section|groupe)$', caseSensitive: false).hasMatch(subj))
        .toSet()
        .toList();
    final subjects = cleanSubjects.isNotEmpty
        ? cleanSubjects.map((name) => (name, _iconForSubject(name))).toList()
        : (s.isFr
            ? const [
                ('Mathématiques', Icons.calculate_outlined),
                ('Physique', Icons.science_outlined),
                ('Chimie', Icons.biotech_outlined),
                ('SVTEEHB', Icons.eco_outlined),
                ('Philosophie', Icons.menu_book_outlined),
                ('Français', Icons.translate_outlined),
                ('Histoire', Icons.history_edu_outlined),
                ('Géographie', Icons.public_outlined),
                ('Anglais', Icons.translate_outlined),
                ('Informatique', Icons.computer_outlined),
                ('Économie', Icons.trending_up_outlined),
                ('Comptabilité', Icons.calculate_outlined),
              ]
            : const [
                ('Mathematics', Icons.calculate_outlined),
                ('Physics', Icons.science_outlined),
                ('Chemistry', Icons.biotech_outlined),
                ('Biology', Icons.eco_outlined),
                ('Computer Science', Icons.computer_outlined),
                ('Economics', Icons.trending_up_outlined),
                ('English Language', Icons.menu_book_outlined),
                ('French', Icons.translate_outlined),
              ]);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          s.exploreTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.exploreSub,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: _searchTopics,
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              widget.onSelectCustomTopic('Independent Study', val.trim());
            }
          },
          decoration: InputDecoration(
            hintText: s.searchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => widget.onSelectCustomTopic(
                      'Independent Study',
                      _searchCtrl.text.trim(),
                    ),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2563EB)),
            ),
          ),
        ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._results.map(
            (t) => Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  t.topicTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${t.subjectName} • ${t.className ?? ""}'),
                trailing: FilledButton.tonal(
                  onPressed: () =>
                      widget.onSelectCustomTopic(t.subjectName, t.topicTitle),
                  child: Text(s.studyWithAi),
                ),
              ),
            ),
          ),
        ] else if (_searchCtrl.text.trim().isNotEmpty && !_searching) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => widget.onSelectCustomTopic(
              'Independent Study',
              _searchCtrl.text.trim(),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              '${s.studyWithAi}: "${_searchCtrl.text.trim()}"',
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          s.browseSubjects,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: subjects.map((item) {
            return InkWell(
              onTap: () => _openSubjectPicker(item.$1),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withAlpha(8),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.$2, color: const Color(0xFF1D4ED8), size: 18),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        item.$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Color(0xFF0F172A),
                          height: 1.2,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          s.exploreTopics,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10,
                          color: Color(0xFF475569),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ProgressJourneyTab extends StatelessWidget {
  final StudentHomeData? home;
  final AppStrings s;
  final void Function(int progressionId) onReviseWithAi;

  const _ProgressJourneyTab({
    required this.home,
    required this.s,
    required this.onReviseWithAi,
  });

  @override
  Widget build(BuildContext context) {
    final data = home;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final total = data.totalTopicsCount;
    final studiedCount = data.understoodCount;
    final gradedCount = data.understoodCount + data.needsRevisionCount;
    final pct = gradedCount > 0
        ? ((data.understoodCount / gradedCount) * 100).round()
        : 0;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          s.myProgress,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.academicJourneySub,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ProgressMetric(
                      value: '$pct%',
                      label: s.avgScore,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  Expanded(
                    child: _ProgressMetric(
                      value: '$studiedCount / $total',
                      label: s.topicsStudied,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ProgressMetric(
                      value: '${data.understoodCount}',
                      label: s.topicsUnderstood,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  Expanded(
                    child: _ProgressMetric(
                      value: '${data.needsRevisionCount}',
                      label: s.topicsToRevise,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          s.subjectPerformance,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        ...() {
          final grouped = <String, List<OfficialProgression>>{};
          final displayNames = <String, String>{};
          for (final t in data.allTopics) {
            final key = t.subjectName.trim().toLowerCase();
            displayNames.putIfAbsent(key, () => t.subjectName.trim());
            grouped.putIfAbsent(key, () => []).add(t);
          }
          for (final subj in data.classSubjects) {
            final key = subj.trim().toLowerCase();
            displayNames.putIfAbsent(key, () => subj.trim());
            grouped.putIfAbsent(key, () => []);
          }
          final entries = grouped.entries.toList()
            ..sort((a, b) {
              final aActive = a.value
                  .where((t) => t.studentStatus != 'not_started')
                  .length;
              final bActive = b.value
                  .where((t) => t.studentStatus != 'not_started')
                  .length;
              if (bActive != aActive) return bActive.compareTo(aActive);
              return (displayNames[a.key] ?? a.key)
                  .compareTo(displayNames[b.key] ?? b.key);
            });
          return entries.map((entry) {
            final topics = entry.value;
            final label = displayNames[entry.key] ?? entry.key;
            final subjTotal = topics.length;
            final subjDone =
                topics.where((t) => t.studentStatus == 'understood').length;
            final subjInProg =
                topics.where((t) => t.studentStatus == 'in_progress').length;
            final subjRev =
                topics.where((t) => t.studentStatus == 'needs_revision').length;
            final subjStudied = subjDone + subjInProg + subjRev;
            final ratio = subjTotal > 0
                ? ((subjDone * 1.0 + subjInProg * 0.45 + subjRev * 0.25) /
                        subjTotal)
                    .clamp(0.0, 1.0)
                : 0.0;
            final subjPct = (ratio * 100).round();
            final firstId = topics.isNotEmpty ? topics.first.id : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: subjStudied > 0
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Text(
                        '$subjPct%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: subjStudied > 0 && ratio < 0.03 ? 0.03 : ratio,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: subjRev > subjDone
                          ? const Color(0xFFD97706)
                          : const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          subjTotal > 0
                              ? '$subjDone understood · $subjInProg in progress / $subjTotal'
                              : (s.isFr
                                  ? 'Programme officiel'
                                  : 'Official syllabus'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      if (firstId != null)
                        TextButton(
                          onPressed: () => onReviseWithAi(firstId),
                          child: Text(s.studyWithAi),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }).toList();
        }(),
      ],
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _ProgressMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final StudentHomeData? home;
  final String userName;
  final String initial;
  final AppStrings s;
  final void Function([int step]) onEditQuestionnaire;

  const _ProfileTab({
    required this.home,
    required this.userName,
    required this.initial,
    required this.s,
    required this.onEditQuestionnaire,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final profile = home?.profile;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          s.myProfile,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (profile != null)
                Text(
                  '${profile.className ?? ""} • ${profile.subsystemName ?? ""}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s.studentAccount,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: Color(0xFF2563EB)),
                title: Text(
                  s.personalInfo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  '${provider.user?.email ?? ""} • ${profile?.age != null ? "${profile!.age} yrs" : ""}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                onTap: () => onEditQuestionnaire(0),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.school_outlined, color: Color(0xFF2563EB)),
                title: Text(
                  s.academicInfo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  '${profile?.subsystemName ?? "-"} • ${profile?.className ?? "-"}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                onTap: () => onEditQuestionnaire(1),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.favorite_border, color: Color(0xFF2563EB)),
                title: Text(
                  s.myInterests,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  profile?.hobbies.isNotEmpty == true
                      ? profile!.hobbies.join(', ')
                      : '-',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                onTap: () => onEditQuestionnaire(4),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.psychology_outlined, color: Color(0xFF2563EB)),
                title: Text(
                  s.learningPrefs,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  profile?.learningStyle ?? '-',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                onTap: () => onEditQuestionnaire(5),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule_outlined, color: Color(0xFF2563EB)),
                title: Text(
                  s.studySchedulePrefs,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  '${profile?.preferredStudyPeriod ?? "evening"} • ${profile?.dailyGoalMinutes ?? 60} min/day',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
                onTap: () => onEditQuestionnaire(6),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.language, color: Color(0xFF2563EB)),
                title: Text(
                  s.languageLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                trailing: _LanguageTogglePill(
                  currentLang: provider.languageCode,
                  onChanged: provider.setLanguage,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => onEditQuestionnaire(0),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF13346B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
          label: Text(
            s.updateQuestionnaire,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
