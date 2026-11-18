class AppUser {
  final int id;
  final String fullName;
  final String email;
  final String role; // 'student' | 'admin'
  final bool questionnaireCompleted;

  AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.questionnaireCompleted,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num).toInt(),
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'student',
      questionnaireCompleted:
          json['questionnaire_completed'] as bool? ?? false,
    );
  }
}

class SchoolClass {
  final int id;
  final int subsystemId;
  final String name;
  final int levelOrder;

  SchoolClass({
    required this.id,
    required this.subsystemId,
    required this.name,
    required this.levelOrder,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> json) {
    return SchoolClass(
      id: (json['id'] as num).toInt(),
      subsystemId: (json['subsystem_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      levelOrder: (json['level_order'] as num?)?.toInt() ?? 1,
    );
  }
}

class Subsystem {
  final int id;
  final String code;
  final String name;
  final String? description;
  final List<SchoolClass> classes;

  Subsystem({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.classes,
  });

  factory Subsystem.fromJson(Map<String, dynamic> json) {
    return Subsystem(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String? ?? 'en',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      classes: (json['classes'] as List<dynamic>? ?? [])
          .map((c) => SchoolClass.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class StudentProfile {
  final int userId;
  final int? subsystemId;
  final String? subsystemName;
  final int? classId;
  final String? className;
  final int? age;
  final bool questionnaireCompleted;
  final String? favouriteSubject;
  final List<String> difficultSubjects;
  final String? difficultyReason;
  final List<String> hobbies;
  final String activityStyle;
  final String learningStyle;
  final String fallbackPreference;
  final String exercisePreference;
  final String preferredStudyPeriod;
  final String? academicGoal;
  final int dailyGoalMinutes;
  final int reminderHour;
  final int reminderMinute;

  StudentProfile({
    required this.userId,
    this.subsystemId,
    this.subsystemName,
    this.classId,
    this.className,
    this.age,
    required this.questionnaireCompleted,
    this.favouriteSubject,
    required this.difficultSubjects,
    this.difficultyReason,
    required this.hobbies,
    required this.activityStyle,
    required this.learningStyle,
    required this.fallbackPreference,
    required this.exercisePreference,
    required this.preferredStudyPeriod,
    this.academicGoal,
    required this.dailyGoalMinutes,
    required this.reminderHour,
    required this.reminderMinute,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    return StudentProfile(
      userId: (json['user_id'] as num).toInt(),
      subsystemId: (json['subsystem_id'] as num?)?.toInt(),
      subsystemName: json['subsystem_name'] as String?,
      classId: (json['class_id'] as num?)?.toInt(),
      className: json['class_name'] as String?,
      age: (json['age'] as num?)?.toInt(),
      questionnaireCompleted:
          json['questionnaire_completed'] as bool? ?? false,
      favouriteSubject: json['favourite_subject'] as String?,
      difficultSubjects: (json['difficult_subjects'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      difficultyReason: json['difficulty_reason'] as String?,
      hobbies: (json['hobbies'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      activityStyle: json['activity_style'] as String? ?? 'both',
      learningStyle:
          json['learning_style'] as String? ?? 'practical_examples',
      fallbackPreference:
          json['fallback_preference'] as String? ?? 'another_example',
      exercisePreference:
          json['exercise_preference'] as String? ?? 'short_quizzes',
      preferredStudyPeriod:
          json['preferred_study_period'] as String? ?? 'evening',
      academicGoal: json['academic_goal'] as String?,
      dailyGoalMinutes: (json['daily_goal_minutes'] as num?)?.toInt() ?? 60,
      reminderHour: (json['reminder_hour'] as num?)?.toInt() ?? 18,
      reminderMinute: (json['reminder_minute'] as num?)?.toInt() ?? 0,
    );
  }
}

class OfficialProgression {
  final int id;
  final int subsystemId;
  final String? subsystemName;
  final int classId;
  final String? className;
  final String subjectName;
  final String topicTitle;
  final String? subtopics;
  final int weekNumber;
  final String startDate;
  final String endDate;
  final String? studyDays;
  final String studentStatus;
  final String understandingLevel;

  OfficialProgression({
    required this.id,
    required this.subsystemId,
    this.subsystemName,
    required this.classId,
    this.className,
    required this.subjectName,
    required this.topicTitle,
    this.subtopics,
    required this.weekNumber,
    required this.startDate,
    required this.endDate,
    this.studyDays,
    required this.studentStatus,
    required this.understandingLevel,
  });

  factory OfficialProgression.fromJson(Map<String, dynamic> json) {
    return OfficialProgression(
      id: (json['id'] as num).toInt(),
      subsystemId: (json['subsystem_id'] as num).toInt(),
      subsystemName: json['subsystem_name'] as String?,
      classId: (json['class_id'] as num).toInt(),
      className: json['class_name'] as String?,
      subjectName: json['subject_name'] as String? ?? '',
      topicTitle: json['topic_title'] as String? ?? '',
      subtopics: json['subtopics'] as String?,
      weekNumber: (json['week_number'] as num?)?.toInt() ?? 1,
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      studyDays: json['study_days'] as String?,
      studentStatus: json['student_status'] as String? ?? 'not_started',
      understandingLevel:
          json['understanding_level'] as String? ?? 'none',
    );
  }
}

class StudentHomeData {
  final AppUser user;
  final StudentProfile profile;
  final List<OfficialProgression> todayTopics;
  final List<OfficialProgression> weeklyTopics;
  final List<OfficialProgression> allTopics;
  final List<String> classSubjects;
  final List<OfficialProgression> programTopics;
  final int understoodCount;
  final int needsRevisionCount;
  final int totalTopicsCount;

  StudentHomeData({
    required this.user,
    required this.profile,
    required this.todayTopics,
    required this.weeklyTopics,
    required this.allTopics,
    this.classSubjects = const [],
    this.programTopics = const [],
    required this.understoodCount,
    required this.needsRevisionCount,
    required this.totalTopicsCount,
  });

  factory StudentHomeData.fromJson(Map<String, dynamic> json) {
    return StudentHomeData(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      profile: StudentProfile.fromJson(json['profile'] as Map<String, dynamic>),
      todayTopics: (json['today_topics'] as List<dynamic>? ?? [])
          .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
          .toList(),
      weeklyTopics: (json['weekly_topics'] as List<dynamic>? ?? [])
          .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
          .toList(),
      allTopics: (json['all_topics'] as List<dynamic>? ?? [])
          .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
          .toList(),
      classSubjects: (json['class_subjects'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      programTopics: (json['program_topics'] as List<dynamic>? ?? [])
          .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
          .toList(),
      understoodCount: (json['understood_count'] as num?)?.toInt() ?? 0,
      needsRevisionCount: (json['needs_revision_count'] as num?)?.toInt() ?? 0,
      totalTopicsCount: (json['total_topics_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminDashboardData {
  final AppUser admin;
  final int subsystemsCount;
  final int classesCount;
  final int studentsCount;
  final int progressionsCount;
  final int programTopicsCount;
  final List<Map<String, dynamic>> recentStudents;
  final List<OfficialProgression> progressions;
  final List<Map<String, dynamic>> uploadedFolders;

  AdminDashboardData({
    required this.admin,
    required this.subsystemsCount,
    required this.classesCount,
    required this.studentsCount,
    required this.progressionsCount,
    this.programTopicsCount = 0,
    required this.recentStudents,
    required this.progressions,
    this.uploadedFolders = const [],
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    return AdminDashboardData(
      admin: AppUser.fromJson(json['admin'] as Map<String, dynamic>),
      subsystemsCount: (json['subsystems_count'] as num?)?.toInt() ?? 2,
      classesCount: (json['classes_count'] as num?)?.toInt() ?? 14,
      studentsCount: (json['students_count'] as num?)?.toInt() ?? 0,
      progressionsCount: (json['progressions_count'] as num?)?.toInt() ?? 0,
      programTopicsCount:
          (json['program_topics_count'] as num?)?.toInt() ?? 0,
      recentStudents: (json['recent_students'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      progressions: (json['progressions'] as List<dynamic>? ?? [])
          .map((e) => OfficialProgression.fromJson(e as Map<String, dynamic>))
          .toList(),
      uploadedFolders: (json['uploaded_folders'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

class QuizQuestion {
  final String question;
  final String questionType;
  final List<String> options;
  final int correctIndex;
  final int marks;
  final List<String> expectedPoints;
  final String explanation;

  QuizQuestion({
    required this.question,
    this.questionType = 'mcq',
    this.options = const [],
    this.correctIndex = 0,
    this.marks = 1,
    this.expectedPoints = const [],
    this.explanation = '',
  });

  bool get isMcq => questionType == 'mcq' && options.isNotEmpty;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] as String? ?? '',
      questionType: json['question_type'] as String? ?? 'mcq',
      options: (json['options'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      marks: (json['marks'] as num?)?.toInt() ?? 1,
      expectedPoints: (json['expected_points'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      explanation: json['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'question_type': questionType,
        'options': options,
        'correct_index': correctIndex,
        'marks': marks,
        'expected_points': expectedPoints,
        'explanation': explanation,
      };
}

class SceneObject {
  final String sprite;
  final String label;
  final double x;
  final double y;
  final String color;
  final double scale;

  SceneObject({
    this.sprite = 'cell',
    this.label = '',
    this.x = 0.5,
    this.y = 0.5,
    this.color = 'blue',
    this.scale = 1.0,
  });

  factory SceneObject.fromJson(Map<String, dynamic> json) {
    return SceneObject(
      sprite: json['sprite'] as String? ?? 'cell',
      label: json['label'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      color: json['color'] as String? ?? 'blue',
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class SceneMotion {
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final String particle;
  final String color;
  final String label;

  SceneMotion({
    this.fromX = 0.2,
    this.fromY = 0.5,
    this.toX = 0.8,
    this.toY = 0.5,
    this.particle = 'drop',
    this.color = 'cyan',
    this.label = '',
  });

  factory SceneMotion.fromJson(Map<String, dynamic> json) {
    return SceneMotion(
      fromX: (json['from_x'] as num?)?.toDouble() ?? 0.2,
      fromY: (json['from_y'] as num?)?.toDouble() ?? 0.5,
      toX: (json['to_x'] as num?)?.toDouble() ?? 0.8,
      toY: (json['to_y'] as num?)?.toDouble() ?? 0.5,
      particle: json['particle'] as String? ?? 'drop',
      color: json['color'] as String? ?? 'cyan',
      label: json['label'] as String? ?? '',
    );
  }
}

class SimulationScene {
  final String environment;
  final List<SceneObject> objects;
  final List<SceneMotion> motions;

  SimulationScene({
    this.environment = 'biology',
    this.objects = const [],
    this.motions = const [],
  });

  factory SimulationScene.fromJson(Map<String, dynamic> json) {
    return SimulationScene(
      environment: json['environment'] as String? ?? 'biology',
      objects: (json['objects'] as List<dynamic>? ?? [])
          .map((e) => SceneObject.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      motions: (json['motions'] as List<dynamic>? ?? [])
          .map((e) => SceneMotion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class SimulationStep {
  final int stepNumber;
  final String title;
  final String action;
  final String visualModel;
  final String outcome;
  final SimulationScene? scene;

  SimulationStep({
    required this.stepNumber,
    required this.title,
    required this.action,
    this.visualModel = '',
    this.outcome = '',
    this.scene,
  });

  factory SimulationStep.fromJson(Map<String, dynamic> json) {
    final rawScene = json['scene'] as Map<String, dynamic>?;
    return SimulationStep(
      stepNumber: (json['step_number'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      action: json['action'] as String? ?? '',
      visualModel: json['visual_model'] as String? ?? '',
      outcome: json['outcome'] as String? ?? '',
      scene: rawScene != null ? SimulationScene.fromJson(rawScene) : null,
    );
  }
}

class SimulationData {
  final String title;
  final String hobbyConnection;
  final String learningStyleFocus;
  final String scenario;
  final List<SimulationStep> steps;
  final String keyTakeaway;

  SimulationData({
    required this.title,
    this.hobbyConnection = '',
    this.learningStyleFocus = '',
    this.scenario = '',
    this.steps = const [],
    this.keyTakeaway = '',
  });

  factory SimulationData.fromJson(Map<String, dynamic> json) {
    return SimulationData(
      title: json['title'] as String? ?? 'Interactive Simulation',
      hobbyConnection: json['hobby_connection'] as String? ?? '',
      learningStyleFocus: json['learning_style_focus'] as String? ?? '',
      scenario: json['scenario'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((e) => SimulationStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      keyTakeaway: json['key_takeaway'] as String? ?? '',
    );
  }
}

class DiagramComparisonRow {
  final String criterion;
  final String leftValue;
  final String rightValue;

  DiagramComparisonRow({
    required this.criterion,
    required this.leftValue,
    required this.rightValue,
  });

  factory DiagramComparisonRow.fromJson(Map<String, dynamic> json) {
    return DiagramComparisonRow(
      criterion: json['criterion'] as String? ?? '',
      leftValue: json['left_value'] as String? ?? '',
      rightValue: json['right_value'] as String? ?? '',
    );
  }
}

class DiagramNode {
  final String id;
  final String label;
  final String detail;
  final String role;

  DiagramNode({
    required this.id,
    required this.label,
    this.detail = '',
    this.role = 'step',
  });

  factory DiagramNode.fromJson(Map<String, dynamic> json) {
    return DiagramNode(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      role: json['role'] as String? ?? 'step',
    );
  }
}

class DiagramEdge {
  final String fromId;
  final String toId;
  final String label;

  DiagramEdge({
    required this.fromId,
    required this.toId,
    this.label = '',
  });

  factory DiagramEdge.fromJson(Map<String, dynamic> json) {
    return DiagramEdge(
      fromId: json['from_id'] as String? ?? '',
      toId: json['to_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class NoteDiagram {
  final String diagramType;
  final String title;
  final String subtitle;
  final String leftLabel;
  final String rightLabel;
  final List<DiagramComparisonRow> comparisonRows;
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;
  final String takeaway;

  NoteDiagram({
    this.diagramType = 'flow',
    required this.title,
    this.subtitle = '',
    this.leftLabel = '',
    this.rightLabel = '',
    this.comparisonRows = const [],
    this.nodes = const [],
    this.edges = const [],
    this.takeaway = '',
  });

  factory NoteDiagram.fromJson(Map<String, dynamic> json) {
    return NoteDiagram(
      diagramType: json['diagram_type'] as String? ?? 'flow',
      title: json['title'] as String? ?? 'Diagram',
      subtitle: json['subtitle'] as String? ?? '',
      leftLabel: json['left_label'] as String? ?? '',
      rightLabel: json['right_label'] as String? ?? '',
      comparisonRows: (json['comparison_rows'] as List<dynamic>? ?? [])
          .map((e) => DiagramComparisonRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      nodes: (json['nodes'] as List<dynamic>? ?? [])
          .map((e) => DiagramNode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      edges: (json['edges'] as List<dynamic>? ?? [])
          .map((e) => DiagramEdge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      takeaway: json['takeaway'] as String? ?? '',
    );
  }
}

class AiResponse {
  final String interactionType;
  final String content;
  final String modelUsed;
  final List<QuizQuestion>? quiz;
  final List<Map<String, String>> sources;
  final List<Map<String, String>> videoSuggestions;
  final List<NoteDiagram> diagrams;
  final SimulationData? simulation;
  final String? scoreSummary;
  final bool progressUpdated;

  AiResponse({
    required this.interactionType,
    required this.content,
    required this.modelUsed,
    this.quiz,
    this.sources = const [],
    this.videoSuggestions = const [],
    this.diagrams = const [],
    this.simulation,
    this.scoreSummary,
    this.progressUpdated = false,
  });

  factory AiResponse.fromJson(Map<String, dynamic> json) {
    final rawQuiz = json['quiz'] as List<dynamic>?;
    final rawSources = json['sources'] as List<dynamic>? ?? [];
    final rawVideos = json['video_suggestions'] as List<dynamic>? ?? [];
    final rawDiagrams = json['diagrams'] as List<dynamic>? ?? [];
    final rawSim = json['simulation'] as Map<String, dynamic>?;
    return AiResponse(
      interactionType: json['interaction_type'] as String? ?? 'chat',
      content: json['content'] as String? ?? '',
      modelUsed: json['model_used'] as String? ?? '',
      quiz: rawQuiz
          ?.map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
      sources: rawSources
          .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
              ))
          .toList(),
      videoSuggestions: rawVideos
          .map((e) => Map<String, String>.from(
                (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
              ))
          .toList(),
      diagrams: rawDiagrams
          .map((e) => NoteDiagram.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      simulation: rawSim != null ? SimulationData.fromJson(rawSim) : null,
      scoreSummary: json['score_summary'] as String?,
      progressUpdated: json['progress_updated'] as bool? ?? false,
    );
  }
}

class AiHistoryItem {
  final int id;
  final int? progressionId;
  final String? subjectName;
  final String? topicTitle;
  final String interactionType;
  final String prompt;
  final String response;
  final List<Map<String, String>> sources;
  final List<NoteDiagram> diagrams;
  final SimulationData? simulation;
  final List<QuizQuestion>? quiz;
  final String? scoreSummary;
  final DateTime? createdAt;

  AiHistoryItem({
    required this.id,
    this.progressionId,
    this.subjectName,
    this.topicTitle,
    required this.interactionType,
    required this.prompt,
    required this.response,
    this.sources = const [],
    this.diagrams = const [],
    this.simulation,
    this.quiz,
    this.scoreSummary,
    this.createdAt,
  });

  factory AiHistoryItem.fromJson(Map<String, dynamic> json) {
    return AiHistoryItem(
      id: (json['id'] as num).toInt(),
      progressionId: (json['progression_id'] as num?)?.toInt(),
      subjectName: json['subject_name'] as String?,
      topicTitle: json['topic_title'] as String?,
      interactionType: json['interaction_type'] as String? ?? 'chat',
      prompt: json['prompt'] as String? ?? '',
      response: json['response'] as String? ?? '',
      sources: (json['sources'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (e) => e.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
          )
          .toList(),
      diagrams: (json['diagrams'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => NoteDiagram.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      simulation: json['simulation'] is Map
          ? SimulationData.fromJson(
              Map<String, dynamic>.from(json['simulation'] as Map),
            )
          : null,
      quiz: (json['quiz'] as List<dynamic>?)
          ?.whereType<Map>()
          .map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      scoreSummary: json['score_summary'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}
