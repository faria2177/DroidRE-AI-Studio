import 'package:flutter/material.dart';

import 'screens/studio_screens.dart';
import 'services/studio_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DroidReApp());
}

class DroidReApp extends StatefulWidget {
  const DroidReApp({super.key});

  @override
  State<DroidReApp> createState() => _DroidReAppState();
}

class _DroidReAppState extends State<DroidReApp> {
  final StudioController controller = StudioController();

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DroidRE AI Studio',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff29d3b0),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xff0b121d),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff29d3b0),
          brightness: Brightness.dark,
          surface: const Color(0xff111c2b),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff0b121d),
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xff142337),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      home: StudioShell(controller: controller),
    );
  }
}
