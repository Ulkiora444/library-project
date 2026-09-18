import 'dart:async';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'library_login_page.dart';
import 'reader_page.dart';
import 'reader_preferences.dart';
import 'reader_theme.dart';
import 'reader_user_session.dart';

class ReaderApp extends StatefulWidget {
  const ReaderApp({super.key});

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  final ReaderPreferences _preferences = ReaderPreferences();
  ReaderThemeChoice _themeChoice = ReaderThemeChoice.paper;
  AppLanguage _languageChoice = AppLanguage.system;
  double _fontScale = 1.0;
  ReaderUserSession? _session;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final saved = await _preferences.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _themeChoice = saved.themeChoice;
      _fontScale = saved.fontScale;
      _languageChoice = saved.languageChoice;
      _session = saved.session;
      _isReady = true;
    });
  }

  void _handleThemeChanged(ReaderThemeChoice value) {
    if (_themeChoice == value) {
      return;
    }

    setState(() {
      _themeChoice = value;
    });
    unawaited(_preferences.saveThemeChoice(value));
  }

  void _handleFontScaleChanged(double value) {
    final clamped = value.clamp(0.8, 1.8);
    if ((_fontScale - clamped).abs() < 0.001) {
      return;
    }

    setState(() {
      _fontScale = clamped;
    });
    unawaited(_preferences.saveFontScale(clamped));
  }

  void _handleLanguageChanged(AppLanguage value) {
    if (_languageChoice == value) {
      return;
    }

    setState(() {
      _languageChoice = value;
    });
    unawaited(_preferences.saveLanguageChoice(value));
  }

  void _handleSignedIn(ReaderUserSession session) {
    setState(() {
      _session = session;
    });
    unawaited(_preferences.saveUserSession(session));
  }

  void _handleUserChanged(ReaderUserSession session) {
    setState(() {
      _session = session;
    });
    unawaited(_preferences.saveUserSession(session));
  }

  void _handleSignedOut() {
    setState(() {
      _session = null;
    });
    unawaited(_preferences.clearUserSession());
  }

  Locale? _resolveLocale(List<Locale>? locales, Iterable<Locale> supported) {
    if (_languageChoice != AppLanguage.system) {
      return _languageChoice.locale;
    }

    final deviceLocale = locales?.firstWhere(
      (locale) => locale.languageCode == 'ru',
      orElse: () => const Locale('en'),
    );
    if (deviceLocale != null && deviceLocale.languageCode == 'ru') {
      return const Locale('ru');
    }
    return const Locale('en');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: _languageChoice.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: _resolveLocale,
      theme: buildAppTheme(_themeChoice),
      home: !_isReady
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _session == null
          ? LibraryLoginPage(
              themeChoice: _themeChoice,
              languageChoice: _languageChoice,
              onThemeChanged: _handleThemeChanged,
              onLanguageChanged: _handleLanguageChanged,
              onSignedIn: _handleSignedIn,
            )
          : ReaderHomePage(
              themeChoice: _themeChoice,
              onThemeChanged: _handleThemeChanged,
              fontScale: _fontScale,
              onFontScaleChanged: _handleFontScaleChanged,
              languageChoice: _languageChoice,
              onLanguageChanged: _handleLanguageChanged,
              currentUser: _session!,
              onUserChanged: _handleUserChanged,
              onSignOut: _handleSignedOut,
            ),
    );
  }
}
