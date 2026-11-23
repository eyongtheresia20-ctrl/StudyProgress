import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../providers/study_provider.dart';
import '../services/supabase_cloud_service.dart';

class NotificationsScreen extends StatefulWidget {
  final void Function(int tabIndex)? onOpenTab;
  final void Function(int? progressionId)? onOpenAiTopic;

  const NotificationsScreen({
    super.key,
    this.onOpenTab,
    this.onOpenAiTopic,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _deepNavy = Color(0xFF13346B);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _growthGreen = Color(0xFF10B981);
  static const Color _aiPurple = Color(0xFF7C3AED);

  final Set<String> _dismissedIds = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('dismissed_notification_ids') ?? [];
    if (mounted) {
      setState(() {
        _dismissedIds.addAll(list);
        _loaded = true;
      });
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() {
      _dismissedIds.add(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dismissed_notification_ids', _dismissedIds.toList());
  }

  Future<void> _clearAll(List<String> allCurrentIds) async {
    setState(() {
      _dismissedIds.addAll(allCurrentIds);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dismissed_notification_ids', _dismissedIds.toList());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les notifications ont été effacées'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final s = AppStrings(provider.languageCode);
    final isFr = provider.languageCode == 'fr';
    final isAdmin = provider.user?.isAdmin == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: Text(
          isAdmin
              ? (isFr ? 'Notifications Admin' : 'Admin Notifications')
              : s.notifications,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _deepNavy,
          ),
        ),
        actions: [
          IconButton(
            tooltip: isFr ? 'Tout effacer' : 'Clear all',
            onPressed: () {
              final home = provider.studentHome;
              final ids = <String>[
                'sunday_briefing',
                'daily_reminder',
                'needs_revision',
                if (home != null) ...home.todayTopics.map((t) => 'topic_${t.id}'),
                if (home != null) ...home.weeklyTopics.map((t) => 'weekly_${t.id}'),
              ];
              _clearAll(ids);
            },
            icon: const Icon(Icons.delete_sweep_outlined, color: _deepNavy),
          ),
          IconButton(
            tooltip: s.refresh,
            onPressed: provider.refreshDashboard,
            icon: const Icon(Icons.refresh_rounded, color: _deepNavy),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : (isAdmin
              ? _buildAdminNotifications(context, provider, isFr)
              : _buildStudentNotifications(context, provider, s, isFr)),
    );
  }

  Widget _buildAdminNotifications(
    BuildContext context,
    StudyProvider provider,
    bool isFr,
  ) {
    final dash = provider.adminDashboard;
    if (dash == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = <Widget>[];

    if (!_dismissedIds.contains('admin_engine')) {
      items.add(
        _NotificationCard(
          icon: Icons.menu_book_outlined,
          color: _primaryBlue,
          badge: isFr ? 'SYSTÈME ACTIF' : 'ACTIVE ENGINE',
          title: isFr ? 'Programme officiel actif' : 'Active Official Programme',
          body: isFr
              ? '${dash.progressionsCount} sujet(s) programmé(s) alimentent les rappels hebdomadaires du dimanche et les plans quotidiens des élèves.'
              : '${dash.progressionsCount} scheduled topic(s) currently power Sunday weekly briefings and daily student schedules.',
          actionLabel: isFr ? 'Accueil Admin' : 'Admin Home',
          onTap: () => Navigator.pop(context),
          onDelete: () => _dismiss('admin_engine'),
        ),
      );
      items.add(const SizedBox(height: 12));
    }

    if (!_dismissedIds.contains('admin_students')) {
      items.add(
        _NotificationCard(
          icon: Icons.people_outline,
          color: _growthGreen,
          badge: isFr ? 'ÉLÈVES' : 'STUDENTS',
          title: isFr ? 'Activité des élèves' : 'Student Registrations',
          body: isFr
              ? '${dash.studentsCount} élève(s) inscrit(s) reçoivent actuellement leurs notifications personnalisées.'
              : '${dash.studentsCount} student(s) currently registered and receiving scheduled reminders.',
          actionLabel: isFr ? 'Voir les élèves' : 'View Students',
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab?.call(1);
          },
          onDelete: () => _dismiss('admin_students'),
        ),
      );
      items.add(const SizedBox(height: 12));
    }

    if (dash.uploadedFolders.isNotEmpty) {
      items.add(const SizedBox(height: 10));
      items.add(
        Text(
          isFr ? 'Historique des dossiers importés' : 'Imported Folder Activity',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _deepNavy,
          ),
        ),
      );
      items.add(const SizedBox(height: 10));

      for (final folder in dash.uploadedFolders) {
        final name = folder['folder_name']?.toString() ?? 'Folder';
        final folderId = 'folder_$name';
        if (_dismissedIds.contains(folderId)) continue;

        final filesCount = (folder['files_count'] as num?)?.toInt() ?? 0;
        final topicsAdded = (folder['topics_added'] as num?)?.toInt() ?? 0;
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NotificationCard(
              icon: Icons.folder_rounded,
              color: _deepNavy,
              badge: isFr ? 'IMPORTÉ' : 'IMPORTED',
              title: name,
              body: isFr
                  ? '$filesCount fichier(s) traité(s) · $topicsAdded sujet(s) ajouté(s).'
                  : '$filesCount file(s) processed · $topicsAdded topic(s) added.',
              onTap: () => Navigator.pop(context),
              onDelete: () => _dismiss(folderId),
            ),
          ),
        );
      }
    }

    if (items.isEmpty) {
      return _buildEmptyState(isFr);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: items,
    );
  }

  Widget _buildStudentNotifications(
    BuildContext context,
    StudyProvider provider,
    AppStrings s,
    bool isFr,
  ) {
    final home = provider.studentHome;
    if (home == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final weeklyTopics = home.weeklyTopics;
    final todayTopics = home.todayTopics;
    final profile = home.profile;
    final reminderTime =
        '${profile.reminderHour.toString().padLeft(2, '0')}:${profile.reminderMinute.toString().padLeft(2, '0')}';

    final weekNum = weeklyTopics.isNotEmpty ? weeklyTopics.first.weekNumber : 1;
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon .. 7=Sun
    final isSaturday = weekday == DateTime.saturday;
    final isSunday = weekday == DateTime.sunday;

    final dayNamesFr = ['', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    final dayNamesEn = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final currentDayName = isFr ? dayNamesFr[weekday] : dayNamesEn[weekday];

    final sundayTitle = isFr
        ? 'Feuille de Route du Dimanche · Semaine $weekNum'
        : 'Sunday Weekly Roadmap • Week $weekNum';
    final sundayBody = weeklyTopics.isNotEmpty
        ? (isFr
            ? 'Ce que nous étudions cette semaine (Semaine $weekNum) : ${weeklyTopics.map((t) => "${t.subjectName}: ${t.topicTitle}").take(4).join(" ; ")}. Révisez vos cours pour bien démarrer !'
            : 'What we will study this week (Week $weekNum): ${weeklyTopics.map((t) => "${t.subjectName}: ${t.topicTitle}").take(4).join("; ")}. Complete your revision and get ready!')
        : s.sundayBriefingBody(0);

    String dailyBadge;
    String dailyTitle;
    String dailyBody;

    if (isSaturday) {
      dailyBadge = isFr ? 'SAMEDI · RÉVISION' : 'SATURDAY · REVISION';
      dailyTitle = isFr ? 'Samedi : Révision Hebdomadaire' : 'Saturday Weekly Revision';
      final revList = todayTopics.isNotEmpty ? todayTopics : weeklyTopics;
      dailyBody = isFr
          ? 'Jour de révision : Consolidez tout ce qui a été étudié du lundi au vendredi (${revList.map((t) => cleanSubjectName(t.subjectName)).toSet().join(", ")}). Testez-vous avec un Quiz IA !'
          : 'Revision Day: Consolidate everything studied Monday through Friday (${revList.map((t) => cleanSubjectName(t.subjectName)).toSet().join(", ")}). Test yourself with an AI Quiz!';
    } else if (isSunday) {
      dailyBadge = isFr ? 'DIMANCHE · BILAN' : 'SUNDAY · REVIEW';
      dailyTitle = isFr ? 'Dimanche : Bilan & Préparation' : 'Sunday Review & Prep';
      dailyBody = isFr
          ? 'Terminez la révision des notions de la semaine et préparez vos cours de lundi.'
          : 'Finish revising topics from the past week and preview Monday\'s schedule.';
    } else {
      dailyBadge = '$currentDayName · $reminderTime';
      dailyTitle = isFr
          ? '$currentDayName : Programme du jour'
          : '$currentDayName Study Plan';
      dailyBody = todayTopics.isNotEmpty
          ? (isFr
              ? "Aujourd'hui ($currentDayName), voici ce que vous étudiez selon le programme officiel (4 leçons maximum) : ${todayTopics.take(4).map((t) => "${cleanSubjectName(t.subjectName)} (${t.topicTitle})").join(", ")}."
              : 'Today ($currentDayName), you will study: ${todayTopics.take(4).map((t) => "${cleanSubjectName(t.subjectName)} (${t.topicTitle})").join(", ")} according to your official syllabus (max 4 lessons).')
          : s.dailyReminderBody(profile.dailyGoalMinutes, reminderTime);
    }

    final firstTopicId = todayTopics.isNotEmpty
        ? todayTopics.first.id
        : (home.allTopics.isNotEmpty ? home.allTopics.first.id : null);

    final items = <Widget>[];

    // Sunday briefing card
    if (!_dismissedIds.contains('sunday_briefing')) {
      items.add(
        _NotificationCard(
          icon: Icons.calendar_today_rounded,
          color: _primaryBlue,
          badge: isFr ? 'DIMANCHE · PROGRAMME DE LA SEMAINE' : 'SUNDAY · WEEKLY BRIEFING',
          title: sundayTitle,
          body: sundayBody,
          actionLabel: s.myProgramme,
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab?.call(1);
          },
          onDelete: () => _dismiss('sunday_briefing'),
        ),
      );
      items.add(const SizedBox(height: 12));
    }

    // Daily reminder card
    if (!_dismissedIds.contains('daily_reminder')) {
      items.add(
        _NotificationCard(
          icon: isSaturday
              ? Icons.auto_stories_rounded
              : (isSunday ? Icons.assessment_outlined : Icons.alarm_rounded),
          color: isSaturday ? _aiPurple : _growthGreen,
          badge: dailyBadge,
          title: dailyTitle,
          body: dailyBody,
          actionLabel: (isSaturday || isSunday)
              ? (isFr ? 'Lancer un Quiz Révision' : 'Start Revision Quiz')
              : (isFr ? 'Étudier aujourd\'hui' : 'Study Today'),
          onTap: () {
            Navigator.pop(context);
            if (isSaturday || isSunday) {
              widget.onOpenTab?.call(3);
            } else if (firstTopicId != null) {
              widget.onOpenAiTopic?.call(firstTopicId);
            } else {
              widget.onOpenTab?.call(1);
            }
          },
          onDelete: () => _dismiss('daily_reminder'),
        ),
      );
      items.add(const SizedBox(height: 12));
    }

    // Revision alert
    if (home.needsRevisionCount > 0 && !_dismissedIds.contains('needs_revision')) {
      items.add(
        _NotificationCard(
          icon: Icons.restart_alt_rounded,
          color: const Color(0xFFD97706),
          badge: isFr ? 'RÉVISION SUGGÉRÉE' : 'REVISION ALERT',
          title: isFr
              ? '${home.needsRevisionCount} sujet(s) nécessitent une révision'
              : '${home.needsRevisionCount} topic(s) need revision',
          body: isFr
              ? 'Vous avez marqué des notions comme non maîtrisées. Ouvrez l\'onglet Progrès pour les réviser avec le tuteur IA.'
              : 'You flagged topics to revisit. Open Progress to review them with AI.',
          actionLabel: isFr ? 'Voir Progrès' : 'View Progress',
          onTap: () {
            Navigator.pop(context);
            widget.onOpenTab?.call(4);
          },
          onDelete: () => _dismiss('needs_revision'),
        ),
      );
      items.add(const SizedBox(height: 12));
    }

    // Today scheduled topics list
    final visibleTopics = todayTopics.where((t) => !_dismissedIds.contains('topic_${t.id}')).toList();
    if (visibleTopics.isNotEmpty) {
      items.add(const SizedBox(height: 6));
      items.add(
        Text(
          isFr ? 'Sujets prévus aujourd’hui (Max 4)' : "Today's Scheduled Topics (Max 4)",
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _deepNavy,
          ),
        ),
      );
      items.add(const SizedBox(height: 10));

      // Calculate time slot per topic
      final totalMins = profile.dailyGoalMinutes > 0 ? profile.dailyGoalMinutes : 60;
      final minsPerTopic = (totalMins / visibleTopics.length).clamp(15, 120).round();
      final startH = profile.reminderHour;
      final startM = profile.reminderMinute;

      for (int i = 0; i < visibleTopics.length; i++) {
        final t = visibleTopics[i];
        final startOffset = i * minsPerTopic;
        final endOffset = (i + 1) * minsPerTopic;
        final tStartH = (startH + (startM + startOffset) ~/ 60) % 24;
        final tStartM = (startM + startOffset) % 60;
        final tEndH = (startH + (startM + endOffset) ~/ 60) % 24;
        final tEndM = (startM + endOffset) % 60;
        final timeStr = '${tStartH.toString().padLeft(2, '0')}:${tStartM.toString().padLeft(2, '0')} - ${tEndH.toString().padLeft(2, '0')}:${tEndM.toString().padLeft(2, '0')}';

        items.add(
          Dismissible(
            key: Key('topic_${t.id}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _dismiss('topic_${t.id}'),
            background: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.only(right: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _primaryBlue.withAlpha(24),
                  child: const Icon(Icons.book_outlined, color: _primaryBlue),
                ),
                title: Text(
                  t.topicTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${t.subjectName} · ⏰ $timeStr'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                      tooltip: isFr ? 'Supprimer' : 'Delete',
                      onPressed: () => _dismiss('topic_${t.id}'),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenAiTopic?.call(t.id);
                },
              ),
            ),
          ),
        );
      }
    }

    if (items.isEmpty) {
      return _buildEmptyState(isFr);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: items,
    );
  }

  Widget _buildEmptyState(bool isFr) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              isFr ? 'Aucune notification' : 'No notifications',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFr
                  ? 'Toutes vos notifications sont lues ou supprimées.'
                  : 'All notifications have been read or deleted.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String badge;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _NotificationCard({
    required this.icon,
    required this.color,
    required this.badge,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withAlpha(28),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (onDelete != null)
                          GestureDetector(
                            onTap: onDelete,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                      ),
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '$actionLabel →',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
