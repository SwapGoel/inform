import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local_prefs.dart';
import '../../data/models.dart';
import '../auto_wallpaper/auto_wallpaper_service.dart';
import '../lock_card/lock_card_notification_service.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameController;
  late bool _autoWallpaperEnabled;
  late bool _lockCardEnabled;
  bool _rotatingNow = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(localPrefsProvider);
    _nameController = TextEditingController(text: prefs.displayName);
    _autoWallpaperEnabled = prefs.autoWallpaperEnabled;
    _lockCardEnabled = prefs.lockCardEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _clearLocalCache() async {
    final dir = await getApplicationSupportDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local cache cleared. Reopen the app to re-sync.')),
      );
    }
  }

  LocalPrefs get _prefs => ref.read(localPrefsProvider);

  Future<void> _toggleAutoWallpaper(bool value) async {
    setState(() => _autoWallpaperEnabled = value);
    await _prefs.setAutoWallpaperEnabled(value);
    await AutoWallpaperService.syncScheduledWork(_prefs);
  }

  Future<void> _toggleLockCard(bool value) async {
    setState(() => _lockCardEnabled = value);
    await _prefs.setLockCardEnabled(value);
    await AutoWallpaperService.syncScheduledWork(_prefs);
    await LockCardNotificationService.setEnabled(
      value,
      _prefs,
      ref.read(contentRepositoryProvider),
    );
  }

  Future<void> _rotateNow() async {
    setState(() => _rotatingNow = true);
    final ok = await AutoWallpaperService.rotateNow();
    if (!mounted) return;
    setState(() => _rotatingNow = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Wallpaper updated' : 'Could not update wallpaper')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(localPrefsProvider);
    final language = ref.watch(languageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
            onSubmitted: (value) => prefs.setDisplayName(value.trim()),
            onEditingComplete: () => prefs.setDisplayName(_nameController.text.trim()),
          ),
          const SizedBox(height: 24),
          const Text('Language'),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('English'),
                selected: language == AppLanguage.en,
                onSelected: (_) {
                  prefs.setLanguage(AppLanguage.en);
                  ref.read(languageProvider.notifier).state = AppLanguage.en;
                },
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('हिन्दी'),
                selected: language == AppLanguage.hi,
                onSelected: (_) {
                  prefs.setLanguage(AppLanguage.hi);
                  ref.read(languageProvider.notifier).state = AppLanguage.hi;
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock screen card'),
            subtitle: const Text(
              'Shows a fact on your lock screen with a "Next" button to see another — no unlocking needed.',
            ),
            value: _lockCardEnabled,
            onChanged: _toggleLockCard,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-rotating wallpaper'),
            subtitle: const Text(
              'Automatically updates your home & lock screen wallpaper every few hours with fresh content.',
            ),
            value: _autoWallpaperEnabled,
            onChanged: _toggleAutoWallpaper,
          ),
          if (_autoWallpaperEnabled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _rotatingNow ? null : _rotateNow,
              icon: _rotatingNow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wallpaper),
              label: const Text('Update wallpaper now'),
            ),
          ],
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _clearLocalCache,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear local content cache'),
          ),
        ],
      ),
    );
  }
}
