import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/onboarding/onboarding_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/games/games_screen.dart';
import 'features/settings/settings_screen.dart';
import 'providers.dart';

class InformApp extends ConsumerWidget {
  const InformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      initialLocation: ref.read(localPrefsProvider).hasOnboarded ? '/' : '/onboarding',
      routes: [
        GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
        GoRoute(path: '/', builder: (context, state) => const HomeShell()),
      ],
    );

    return MaterialApp.router(
      title: 'Inform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5B21B6), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B21B6),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [FeedScreen(), GamesScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.extension_outlined), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
