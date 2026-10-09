import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'themeMode';

/// Loaded once in main() so the first frame already has the right theme.
final initialThemeModeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

Future<ThemeMode> loadThemeMode() async {
  final p = await SharedPreferences.getInstance();
  return ThemeMode.values.firstWhere((m) => m.name == p.getString(_key), orElse: () => ThemeMode.system);
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> set(ThemeMode m) async {
    state = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, m.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
