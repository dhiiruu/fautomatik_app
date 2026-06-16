import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/app_theme.dart';
import 'state/providers.dart';
import 'services/unlock_notifier.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(
    const ProviderScope(
      child: FautomatikApp(),
    ),
  );
}

class FautomatikApp extends StatelessWidget {
  const FautomatikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fautomatik',
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}

// ignore: unused_element
class _UnlockScreen extends StatelessWidget {
  final UnlockState unlockState;
  final WidgetRef ref;
  const _UnlockScreen({required this.unlockState, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: const Icon(Icons.lock, color: AppTheme.error, size: 36),
              ),
              const SizedBox(height: 24),
              const Text('Fautomatik', style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: 2, color: AppTheme.textPrimary,
              )),
              const SizedBox(height: 12),
              const Text(
                'Watch a rewarded ad to unlock\nall features for 2 hours',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
              ),
              if (unlockState.error != null) ...[
                const SizedBox(height: 12),
                Text(unlockState.error!, style: const TextStyle(color: AppTheme.error, fontSize: 13), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => ref.read(unlockNotifierProvider.notifier).watchAd(),
                icon: const Icon(Icons.play_circle, size: 20),
                label: const Text('Watch Ad to Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
