import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/map_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const GeoViewer3DApp(),
    ),
  );
}

class GeoViewer3DApp extends StatelessWidget {
  const GeoViewer3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoViewer 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1A2E),
        ),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const MapScreen(),
    );
  }
}
