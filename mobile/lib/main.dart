import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/study_provider.dart';
import 'screens/admin_home_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/questionnaire_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/student_home_screen.dart';
import 'services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => StudyProvider()..bootstrap(),
      child: const StudyProgressApp(),
    ),
  );
}

class StudyProgressApp extends StatelessWidget {
  const StudyProgressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kivora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF0F172A)),
          bodyMedium: TextStyle(color: Color(0xFF0F172A)),
          bodySmall: TextStyle(color: Color(0xFF334155)),
        ),
        useMaterial3: true,
      ),
      home: const AppRootRouter(),
    );
  }
}

class AppRootRouter extends StatelessWidget {
  const AppRootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();

    if (provider.isBootstrapping) {
      return const SplashScreen();
    }

    if (!provider.isAuthenticated) {
      return const AuthScreen();
    }

    final user = provider.user!;
    if (user.isAdmin) {
      return const AdminHomeScreen();
    }

    if (!user.questionnaireCompleted) {
      return const QuestionnaireScreen();
    }

    return const StudentHomeScreen();
  }
}
