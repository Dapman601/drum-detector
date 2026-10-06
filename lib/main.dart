import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/results_screen.dart';
import 'screens/report_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    // media_kit init may fail on some devices; app still works for processing
  }
  runApp(const ProviderScope(child: DrumDetectorApp()));
}

class DrumDetectorApp extends StatelessWidget {
  const DrumDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drum Detector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/processing': (_) => const ProcessingScreen(),
        '/results': (_) => const ResultsScreen(),
        '/report': (_) => const ReportScreen(),
      },
    );
  }
}
