import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:study_progress/main.dart';
import 'package:study_progress/models/study_models.dart';
import 'package:study_progress/providers/study_provider.dart';
import 'package:study_progress/widgets/teacher_notes_view.dart';

void main() {
  testWidgets('Kivora app shows SplashScreen while bootstrapping',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => StudyProvider(),
        child: const StudyProgressApp(),
      ),
    );

    expect(find.text('Kivora'), findsOneWidget);
    expect(find.text('Learn. Grow. Become.'), findsOneWidget);
  });

  testWidgets('TeacherNotesView & DiagramCard render clean tables, diagrams & video player',
      (WidgetTester tester) async {
    const sampleNotes = '''
# Sole Proprietorship Lesson
## Quick Comparison
**Teacher Tip:** Focus on liability differences.

| Feature | Sole Trader | Partnership |
| --- | --- | --- |
| Owners | 1 person | 2-20 people |
''';
    final comparison = NoteDiagram(
      diagramType: 'comparison',
      title: 'Sole Trader vs Partnership',
      leftLabel: 'Sole Trader',
      rightLabel: 'Partnership',
      comparisonRows: [
        DiagramComparisonRow(
          criterion: 'Capital',
          leftValue: 'Personal savings',
          rightValue: 'Pooled capital',
        ),
      ],
    );
    final sim = SimulationData(
      title: 'Business Setup Animation',
      steps: [
        SimulationStep(
          stepNumber: 1,
          title: 'Scene 1',
          action: 'Owner invests capital.',
          visualModel: '[Owner] ---> [Shop]',
          outcome: 'Full control',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const TeacherNotesView(content: sampleNotes),
                DiagramCard(diagram: comparison),
                AiVideoExplainerPlayer(simulation: sim, isFr: false),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sole Proprietorship Lesson'), findsOneWidget);
    expect(find.text('# Sole Proprietorship Lesson'), findsNothing);
    expect(find.text('Sole Trader vs Partnership'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('Play AI Video'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AiVideoExplainerPlayer),
        matching: find.byType(CustomPaint),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('AiVideoExplainerPlayer renders plant xylem simulation & voice toggle',
      (WidgetTester tester) async {
    final plantSim = SimulationData(
      title: 'Water Transport in Plants',
      steps: [
        SimulationStep(
          stepNumber: 1,
          title: 'System Balance',
          action: 'Water moves from soil through roots and xylem to leaves.',
          outcome: 'Turgor pressure keeps the plant upright.',
          scene: SimulationScene(
            environment: 'nature',
            objects: [
              SceneObject(sprite: 'stem', label: 'Plant Stem', x: 0.5, y: 0.5),
              SceneObject(sprite: 'drop', label: 'Turgor Pressure', x: 0.5, y: 0.5),
            ],
            motions: [
              SceneMotion(
                fromX: 0.5,
                fromY: 0.5,
                toX: 0.5,
                toY: 0.5,
                particle: 'drop',
              ),
            ],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiVideoExplainerPlayer(simulation: plantSim, isFr: false),
          ),
        ),
      ),
    );

    expect(find.text('Voice'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Voice'));
    await tester.pump();
    expect(find.text('Muted'), findsOneWidget);
  });

  testWidgets('AiVideoExplainerPlayer adapts visuals across Math, CS & Geography',
      (WidgetTester tester) async {
    final multiSubjectSim = SimulationData(
      title: 'Cross-Subject Visual Adaptations',
      steps: [
        SimulationStep(
          stepNumber: 1,
          title: 'Quadratic Equations in Algebra',
          action: 'Plot the parabola on coordinate axes and check roots.',
          outcome: 'Graph shows x-intercepts clearly.',
        ),
        SimulationStep(
          stepNumber: 2,
          title: 'CPU Binary Processing',
          action: 'Algorithm processes inputs inside CPU and stores in database.',
          outcome: 'Clean digital data flow.',
        ),
        SimulationStep(
          stepNumber: 3,
          title: 'Geography Water Cycle',
          action: 'Evaporation rises to form rain clouds over mountains.',
          outcome: 'Rain feeds the river back to sea.',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiVideoExplainerPlayer(simulation: multiSubjectSim, isFr: false),
          ),
        ),
      ),
    );

    expect(find.text('Quadratic Equations in Algebra'), findsOneWidget);
    await tester.ensureVisible(find.text('2'));
    await tester.tap(find.text('2'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CPU Binary Processing'), findsOneWidget);
    await tester.ensureVisible(find.text('3'));
    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Geography Water Cycle'), findsOneWidget);
  });
}
