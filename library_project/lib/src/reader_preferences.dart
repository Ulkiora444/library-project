import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';
import 'reader_theme.dart';
import 'reader_user_session.dart';

class ReaderPreferences {
  static const String _themeKey = 'reader_theme';
  static const String _fontScaleKey = 'reader_font_scale';
  static const String _languageKey = 'reader_language';
  static const String _sessionNameKey = 'reader_session_name';
  static const String _sessionEmailKey = 'reader_session_email';
  static const String _sessionPhoneKey = 'reader_session_phone';
  static const String _sessionGuestKey = 'reader_session_guest';
  static const String _sessionCategoryPickerPendingKey =
      'reader_session_category_picker_pending';
  static const String _sessionWelcomeBannerPendingKey =
      'reader_session_welcome_banner_pending';
  static const String _homeCategoryIdsKey = 'reader_home_category_ids';

  Future<ReaderPreferencesData> load() async {
    final prefs = await SharedPreferences.getInstance();

    return ReaderPreferencesData(
      themeChoice: _readThemeChoice(prefs),
      fontScale: _readFontScale(prefs),
      languageChoice: _readLanguageChoice(prefs),
      session: _readUserSession(prefs),
    );
  }

  Future<void> saveThemeChoice(ReaderThemeChoice value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value.name);
  }

  Future<void> saveFontScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, value.clamp(0.8, 1.8));
  }

  Future<void> saveLanguageChoice(AppLanguage value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, value.name);
  }

  Future<void> saveUserSession(ReaderUserSession value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionNameKey, value.displayName.trim());
    await prefs.setString(_sessionEmailKey, value.email.trim());
    await prefs.setString(_sessionPhoneKey, value.phoneNumber.trim());
    await prefs.setBool(
      _sessionCategoryPickerPendingKey,
      value.categoryPickerPending,
    );
    await prefs.setBool(
      _sessionWelcomeBannerPendingKey,
      value.welcomeBannerPending,
    );
    await prefs.setBool(_sessionGuestKey, value.isGuest);
  }

  Future<List<String>> loadHomeCategoryIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_homeCategoryIdsKey) ?? const [];
  }

  Future<void> saveHomeCategoryIds(Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized =
        ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList()
          ..sort();
    await prefs.setStringList(_homeCategoryIdsKey, normalized);
  }

  Future<void> clearUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionNameKey);
    await prefs.remove(_sessionEmailKey);
    await prefs.remove(_sessionPhoneKey);
    await prefs.remove(_sessionCategoryPickerPendingKey);
    await prefs.remove(_sessionWelcomeBannerPendingKey);
    await prefs.remove(_sessionGuestKey);
  }

  ReaderThemeChoice _readThemeChoice(SharedPreferences prefs) {
    final stored = prefs.getString(_themeKey);
    if (stored == null || stored.isEmpty) {
      return ReaderThemeChoice.paper;
    }

    for (final choice in ReaderThemeChoice.values) {
      if (choice.name == stored) {
        return choice;
      }
    }

    return ReaderThemeChoice.paper;
  }

  AppLanguage _readLanguageChoice(SharedPreferences prefs) {
    final stored = prefs.getString(_languageKey);
    if (stored == null || stored.isEmpty) {
      return AppLanguage.system;
    }

    for (final choice in AppLanguage.values) {
      if (choice.name == stored) {
        return choice;
      }
    }

    return AppLanguage.system;
  }

  double _readFontScale(SharedPreferences prefs) {
    final value = prefs.getDouble(_fontScaleKey);
    if (value == null) {
      return 1.0;
    }

    return value.clamp(0.8, 1.8);
  }

  ReaderUserSession? _readUserSession(SharedPreferences prefs) {
    final isGuest = prefs.getBool(_sessionGuestKey) ?? false;
    final displayName = prefs.getString(_sessionNameKey)?.trim() ?? '';
    final email = prefs.getString(_sessionEmailKey)?.trim() ?? '';
    final phoneNumber = prefs.getString(_sessionPhoneKey)?.trim() ?? '';
    final categoryPickerPending =
        prefs.getBool(_sessionCategoryPickerPendingKey) ?? false;
    final welcomeBannerPending =
        prefs.getBool(_sessionWelcomeBannerPendingKey) ?? false;

    if (!isGuest &&
        displayName.isEmpty &&
        email.isEmpty &&
        phoneNumber.isEmpty) {
      return null;
    }

    if (isGuest &&
        displayName.isEmpty &&
        email.isEmpty &&
        phoneNumber.isEmpty) {
      return const ReaderUserSession(
        displayName: '',
        email: '',
        phoneNumber: '',
        isGuest: true,
      );
    }

    return ReaderUserSession(
      displayName: displayName,
      email: email,
      phoneNumber: phoneNumber,
      categoryPickerPending: categoryPickerPending,
      welcomeBannerPending: welcomeBannerPending,
      isGuest: isGuest,
    );
  }
}

class ReaderPreferencesData {
  const ReaderPreferencesData({
    required this.themeChoice,
    required this.fontScale,
    required this.languageChoice,
    required this.session,
  });

  final ReaderThemeChoice themeChoice;
  final double fontScale;
  final AppLanguage languageChoice;
  final ReaderUserSession? session;
}
