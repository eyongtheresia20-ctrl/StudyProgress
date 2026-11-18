import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/study_provider.dart';

class NotificationsScreen extends StatelessWidget {
  final void Function(int tabIndex)? onOpenTab;
  final void Function(int? progressionId)? onOpenAiTopic;

  const NotificationsScreen({
    super.key,
    this.onOpenTab,
    this.onOpenAiTopic,
  });

  static const Color _deepNavy = Color(0xFF13346B);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _growthGreen = Color(0xFF10B981);
  static const Color _aiPurple = Color(0xFF7C3AED);

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
            tooltip: s.refresh,
            onPressed: provider.refreshDashboard,
            icon: const Icon(Icons.refresh_rounded, color: _deepNavy),
          ),
        ],
      ),
      body: isAdmin
          ? _buildAdminNotifications(context, provider, isFr)
          : _buildStudentNotifications(context, provider, s, isFr),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        ),
        const SizedBox(height: 12),
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
            onOpenTab?.call(1);
          },
        ),
        if (dash.uploadedFolders.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            isFr ? 'Historique des dossiers importés' : 'Imported Folder Activity',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _deepNavy,
            ),
          ),
          const SizedBox(height: 10),
          ...dash.uploadedFolders.map((folder) {
            final name = folder['folder_name']?.toString() ?? 'Folder';
            final filesCount = (folder['files_count'] as num?)?.toInt() ?? 0;
            final topicsAdded = (folder['topics_added'] as num?)?.toInt() ?? 0;
            return Padding(
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
              ),
            );
          }),
        ],
      ],
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
            ? 'Ce que nous étudions cette semaine (Semaine $weekNum) : ${weeklyTopics.map((t) => '${t.subjectName}: ${t.topicTitle}').take(6).join(' ; ')}. Révisez ce qui a été vu pendant la semaine pour bien démarrer !'
            : 'What we will study this week (Week $weekNum): ${weeklyTopics.map((t) => '${t.subjectName}: ${t.topicTitle}').take(6).join('; ')}. Complete your revision of last week\'s lessons and get ready for Monday!')
        : s.sundayBriefingBody(0);

    String dailyBadge;
    String dailyTitle;
    String dailyBody;

    if (isSaturday) {
      dailyBadge = isFr ? 'SAMEDI · RÉVISION' : 'SATURDAY · REVISION';
      dailyTitle = isFr ? 'Samedi : Révision Hebdomadaire' : 'Saturday Weekly Revision';
      final revList = todayTopics.isNotEmpty ? todayTopics : weeklyTopics;
      dailyBody = isFr
          ? 'Jour de révision : Consolidez tout ce qui a été étudié du lundi au vendredi (${revList.map((t) => t.subjectName).toSet().join(', ')}). Testez-vous avec un Quiz IA !'
          : 'Revision Day: Consolidate everything studied Monday through Friday (${revList.map((t) => t.subjectName).toSet().join(', ')}). Test yourself with a quick AI Quiz!';
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
              ? "Aujourd'hui ($currentDayName), voici ce que vous étudiez selon le programme officiel : ${todayTopics.map((t) => '${t.subjectName} (${t.topicTitle})').join(', ')}."
              : 'Today ($currentDayName), you will study: ${todayTopics.map((t) => '${t.subjectName} (${t.topicTitle})').join(', ')} according to your official syllabus.')
          : s.dailyReminderBody(profile.dailyGoalMinutes, reminderTime);
    }

    final firstTopicId = todayTopics.isNotEmpty
        ? todayTopics.first.id
        : (home.allTopics.isNotEmpty ? home.allTopics.first.id : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NotificationCard(
          icon: Icons.calendar_today_rounded,
          color: _primaryBlue,
          badge: isFr ? 'DIMANCHE · HEBDO' : 'SUNDAY BRIEFING',
          title: sundayTitle,
          body: sundayBody,
          actionLabel: isFr ? 'Voir Programme' : 'Open Program',
          onTap: () {
            Navigator.pop(context);
            onOpenTab?.call(1);
          },
        ),
        const SizedBox(height: 12),
        _NotificationCard(
          icon: isSaturday
              ? Icons.replay_circle_filled_rounded
              : Icons.alarm_rounded,
          color: isSaturday ? const Color(0xFFD97706) : _growthGreen,
          badge: dailyBadge,
          title: dailyTitle,
          body: dailyBody,
          actionLabel: isSaturday
              ? (isFr ? 'Réviser maintenant' : 'Revise Now')
              : (isFr ? 'Étudier maintenant' : 'Study Now'),
          onTap: () {
            Navigator.pop(context);
            onOpenAiTopic?.call(firstTopicId);
          },
        ),
        const SizedBox(height: 12),
        _NotificationCard(
          icon: Icons.auto_awesome_rounded,
          color: _aiPurple,
          badge: isFr ? 'TUTEUR IA' : 'AI CHECK',
          title: s.understandingCheckTitle,
          body: s.understandingCheckBody,
          actionLabel: isFr ? 'Parler à l’IA' : 'Open AI Tutor',
          onTap: () {
            Navigator.pop(context);
            onOpenAiTopic?.call(firstTopicId);
          },
        ),
        if (home.needsRevisionCount > 0) ...[
          const SizedBox(height: 12),
          _NotificationCard(
            icon: Icons.replay_circle_filled_rounded,
            color: const Color(0xFFD97706),
            badge: isFr ? 'À RÉVISER' : 'REVISION DUE',
            title: isFr
                ? '${home.needsRevisionCount} sujet(s) à réviser'
                : '${home.needsRevisionCount} topic(s) need revision',
            body: isFr
                ? 'Ouvrez vos progrès pour revoir les notions difficiles avec l’IA.'
                : 'Open your progress view to revise difficult concepts with Kivora AI.',
            actionLabel: isFr ? 'Voir Progrès' : 'View Progress',
            onTap: () {
              Navigator.pop(context);
              onOpenTab?.call(4);
            },
          ),
        ],
        if (todayTopics.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            isFr ? 'Sujets prévus aujourd’hui' : "Today's Scheduled Topics",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _deepNavy,
            ),
          ),
          const SizedBox(height: 10),
          ...todayTopics.map(
            (t) => Container(
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
                subtitle: Text('${t.subjectName} · ${t.studyDays ?? ''}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  onOpenAiTopic?.call(t.id);
                },
              ),
            ),
          ),
        ],
      ],
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

  const _NotificationCard({
    required this.icon,
    required this.color,
    required this.badge,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onTap,
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

