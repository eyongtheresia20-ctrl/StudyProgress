class AppStrings {
  final String lang;
  const AppStrings(this.lang);

  bool get isFr => lang == 'fr';

  // Navigation tabs
  String get navHome => isFr ? 'Accueil' : 'Home';
  String get navProgram => isFr ? 'Programme' : 'Program';
  String get navExplore => isFr ? 'Explorer' : 'Explore';
  String get navProgress => isFr ? 'Progrès' : 'Progress';
  String get navProfile => isFr ? 'Profil' : 'Profile';

  // AppBar & Actions
  String get notifications => isFr ? 'Notifications' : 'Notifications';
  String get refresh => isFr ? 'Actualiser' : 'Refresh';
  String get signOut => isFr ? 'Déconnexion' : 'Sign Out';
  String get askAiTutor => isFr ? 'Tuteur IA Kivora' : 'Kivora AI Tutor';

  // Home Dashboard
  String hello(String name) => isFr ? 'Bonjour, $name !' : 'Hello, $name!';
  String welcomeStudent(String name) =>
      isFr ? 'Bienvenue, $name !' : 'Welcome, $name!';
  String get readyToProgress => isFr
      ? 'Prêt(e) à progresser aujourd’hui ?'
      : 'Ready to make progress today?';
  String get todaysProgrammeBadge =>
      isFr ? 'PROGRAMME DU JOUR' : "TODAY'S PROGRAMME";
  String get yourLearningPlan =>
      isFr ? 'Votre programme du jour' : "Today's learning plan";
  String scheduledCountText(int count) => isFr
      ? 'Vous avez $count sujet(s) à faire aujourd’hui.'
      : 'You have $count topic(s) to do today.';
  String get noTopicTodayHint => isFr
      ? 'Aucun sujet prévu aujourd’hui — explorez le programme de la semaine ou parlez au tuteur IA.'
      : 'No topic scheduled specifically for today — explore this week’s program or ask Kivora AI.';
  String get upcoming => isFr ? 'À venir' : 'Upcoming';
  String get completed => isFr ? 'Terminé' : 'Completed';
  String get inProgress => isFr ? 'En cours' : 'In progress';
  String get startLesson => isFr ? 'Commencer la leçon' : 'Start lesson';
  String get continueLearning =>
      isFr ? 'Continuer l’apprentissage' : 'Continue learning';
  String get seeAll => isFr ? 'Tout voir' : 'See all';
  String get lessonInProgress =>
      isFr ? 'Leçon en cours' : 'Lesson in progress';
  String get continueBtn => isFr ? 'Continuer' : 'Continue';
  String get fullProgramme => isFr ? 'Voir le programme complet' : 'View Full Program';
  String get studyWithAi => isFr ? 'Étudier avec IA' : 'Study with AI';
  String get learningAtGlance =>
      isFr ? 'Votre apprentissage en bref' : 'Your learning at a glance';
  String get topicsStudied => isFr ? 'Sujets étudiés' : 'Topics studied';
  String get topicsUnderstood =>
      isFr ? 'Sujets maîtrisés' : 'Topics understood';
  String get needHelpTitle =>
      isFr ? 'Besoin d’aide sur un sujet ?' : 'Need help with something?';
  String get needHelpSub => isFr
      ? 'Votre tuteur IA est prêt à expliquer les notions difficiles.'
      : 'Your AI tutor is ready to explain difficult topics.';
  String get talkToAi => isFr ? 'Parler au Tuteur IA' : 'Talk to AI Tutor';

  // My Programme Tab
  String get myProgramme => isFr ? 'Mon Programme' : 'My Programme';
  String get tabDaily => isFr ? 'Quotidien' : 'Daily';
  String get tabWeekly => isFr ? 'Hebdo' : 'Weekly';
  String get tabFullYear => isFr ? 'Année complète' : 'Full year';
  String get scheduled => isFr ? 'Prévu' : 'Scheduled';
  String get thisWeekProgression =>
      isFr ? 'Progression de cette semaine' : "This week's progression";
  String get noProgramTopics => isFr
      ? 'Aucun chapitre officiel publié pour votre classe.'
      : 'No official progression uploaded for your class yet.';
  String weekLabel(int week) => isFr ? 'Semaine $week' : 'Week $week';

  // Explore & Learn Tab
  String get exploreTitle => isFr ? 'Explorer & Apprendre' : 'Explore & Learn';
  String get exploreSub => isFr
      ? 'Curieux d’un sujet ? Apprenons-le ensemble.'
      : "Curious about something? Let's learn it together.";
  String get searchHint => isFr
      ? 'Rechercher une matière ou un sujet...'
      : 'Search any subject or topic...';
  String get browseSubjects => isFr ? 'Parcourir les matières' : 'Browse subjects';
  String get exploreTopics => isFr ? 'Explorer les sujets' : 'Explore topics';

  // Progress Tab
  String get myProgress => isFr ? 'Mes Progrès' : 'My Progress';
  String get academicJourneySub => isFr
      ? 'Votre parcours académique en un coup d’œil.'
      : 'Your academic journey at a glance.';
  String get avgScore =>
      isFr ? 'Taux de maîtrise moyen' : 'Average mastery score';
  String get topicsCompleted => isFr ? 'Sujets terminés' : 'Topics completed';
  String get topicsToRevise => isFr ? 'Sujets à réviser' : 'Topics to revise';
  String get subjectPerformance =>
      isFr ? 'Performance par matière' : 'Subject performance';
  String get aiRecommendation =>
      isFr ? 'Recommandation IA' : 'AI recommendation';

  // Notifications Sheet
  String get sundayBriefingTitle => isFr
      ? 'Résumé hebdomadaire du dimanche'
      : 'Sunday Weekly Briefing';
  String sundayBriefingBody(int count) => isFr
      ? 'Vous avez $count sujet(s) prévu(s) cette semaine.'
      : 'You have $count topic(s) scheduled this week.';
  String get dailyReminderTitle =>
      isFr ? 'Rappel quotidien d’étude' : 'Daily Study Reminder';
  String dailyReminderBody(int mins, String time) => isFr
      ? 'Objectif du jour : $mins min. Rappel prévu à $time.'
      : 'Daily target: $mins min. Scheduled reminder at $time.';
  String get understandingCheckTitle =>
      isFr ? 'Vérification de compréhension' : 'Understanding Check';
  String get understandingCheckBody => isFr
      ? 'Testez vos connaissances avec le Tuteur IA sur le sujet du jour.'
      : 'Test your understanding with Kivora AI on today’s topic.';

  // Profile Tab
  String get myProfile => isFr ? 'Mon Profil' : 'My Profile';
  String get studentAccount => isFr ? 'Compte élève' : 'Student account';
  String get personalInfo =>
      isFr ? 'Informations personnelles' : 'Personal information';
  String get academicInfo =>
      isFr ? 'Informations académiques' : 'Academic information';
  String get myInterests => isFr ? 'Mes centres d’intérêt' : 'My interests';
  String get learningPrefs =>
      isFr ? 'Préférences d’apprentissage' : 'Learning preferences';
  String get studySchedulePrefs =>
      isFr ? 'Horaires d’étude & rappels' : 'Study schedule preferences';
  String get languageLabel => isFr ? 'Langue' : 'Language';
  String get updateQuestionnaire =>
      isFr ? 'Modifier le questionnaire' : 'Update Questionnaire';

  // AI Tutor History & Multimodal
  String get aiHistoryTitle =>
      isFr ? 'Historique des recherches' : 'Search History';
  String get aiSearchHistoryHint =>
      isFr ? 'Rechercher dans l’historique...' : 'Search history...';
  String get aiNoHistory => isFr
      ? 'Aucune recherche IA pour le moment.'
      : 'No AI searches yet.';
  String get aiNewChat => isFr ? 'Nouveau' : 'New';
  String get aiAttachPicture => isFr ? 'Photo' : 'Picture';
  String get aiRecordVoice => isFr ? 'Vocal' : 'Voice';
  String get aiStopRecording => isFr ? 'Arrêter' : 'Stop';
  String get aiAttachAudio => isFr ? 'Audio' : 'Audio file';
  String get aiModeAsk => isFr ? 'Poser une question' : 'Ask AI';
  String get aiModeQuiz => isFr ? 'Quiz' : 'Quiz Me';
  String get aiModeSummary => isFr ? 'Résumé' : 'Summary';
  String get aiPromptLabel => isFr
      ? 'Que souhaitez-vous comprendre ?'
      : 'What would you like help understanding?';
  String get aiPromptHint => isFr
      ? 'Ex: Explique étape par étape, ou joignez une photo / note vocale'
      : 'e.g. Ask a question or attach a picture / voice note';
  String get aiAskButton =>
      isFr ? 'Demander au Tuteur IA' : 'Ask Personalized AI Tutor';
  String get cancel => isFr ? 'Annuler' : 'Cancel';
  String get delete => isFr ? 'Supprimer' : 'Delete';
}
