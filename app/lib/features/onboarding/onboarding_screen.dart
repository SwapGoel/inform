import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  AppLanguage _selectedLanguage = AppLanguage.en;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = ref.read(localPrefsProvider);
    await prefs.setDisplayName(_nameController.text.trim());
    await prefs.setLanguage(_selectedLanguage);
    await prefs.setHasOnboarded(true);
    ref.read(languageProvider.notifier).state = _selectedLanguage;
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome to Inform', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('A little general knowledge, every time you unlock your phone.'),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Language'),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('English'),
                    selected: _selectedLanguage == AppLanguage.en,
                    onSelected: (_) => setState(() => _selectedLanguage = AppLanguage.en),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('हिन्दी'),
                    selected: _selectedLanguage == AppLanguage.hi,
                    onSelected: (_) => setState(() => _selectedLanguage = AppLanguage.hi),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _finish, child: const Text('Continue')),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: _finish, child: const Text('Skip')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
