import 'package:flutter/material.dart';
import 'package:sasa_core/sasa_core.dart';

void main() {
  runApp(const SasaApp());
}

/// Root widget of the Sasa app.
class SasaApp extends StatelessWidget {
  const SasaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
    return MaterialApp(
      title: 'Sasa',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: const PlaceholderScreen(),
    );
  }
}

/// Temporary home screen shown until the Today screen exists.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sasaGreeting, style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                placeholderMessage(),
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
