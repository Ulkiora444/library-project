import 'dart:async';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'library_api.dart';
import 'reader_theme.dart';
import 'reader_user_session.dart';

class LibraryLoginPage extends StatefulWidget {
  const LibraryLoginPage({
    super.key,
    required this.themeChoice,
    required this.languageChoice,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    required this.onSignedIn,
  });

  final ReaderThemeChoice themeChoice;
  final AppLanguage languageChoice;
  final ValueChanged<ReaderThemeChoice> onThemeChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<ReaderUserSession> onSignedIn;

  @override
  State<LibraryLoginPage> createState() => _LibraryLoginPageState();
}

class _LibraryLoginPageState extends State<LibraryLoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _authError;
  int _loginStep = 0;
  ReaderUserSession? _pendingSession;

  ReaderPalette get _palette => widget.themeChoice.palette;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    unawaited(_submitAsync());
  }

  Future<void> _submitAsync() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final name = _isRegistering ? _nameController.text.trim() : '';
    final email = _isRegistering ? _emailController.text.trim() : '';
    final phone = _phoneController.text.trim();

    setState(() {
      _isSubmitting = true;
      _authError = null;
    });

    try {
      final session = _isRegistering
          ? await LibraryApiClient.instance.register(
              username: name,
              phone: phone,
              email: email,
              password: _passwordController.text,
            )
          : await LibraryApiClient.instance.login(
              login: phone,
              password: _passwordController.text,
            );

      if (!mounted) {
        return;
      }

      _completeLogin(
        session.copyWith(
          categoryPickerPending: _isRegistering,
          welcomeBannerPending: true,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _authError = _authErrorText(l10n);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _authErrorText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0432\u043e\u0439\u0442\u0438. \u041f\u0440\u043e\u0432\u0435\u0440\u044c\u0442\u0435 backend, \u043b\u043e\u0433\u0438\u043d \u0438 \u043f\u0430\u0440\u043e\u043b\u044c.'
      : 'Could not sign in. Check the backend, login, and password.';

  void _continueAsGuest() {
    _completeLogin(
      const ReaderUserSession(
        displayName: '',
        email: '',
        phoneNumber: '',
        isGuest: true,
      ),
    );
  }

  void _completeLogin(ReaderUserSession session) {
    setState(() {
      _pendingSession = session;
      _loginStep = 3;
    });
  }

  void _finishLogin() {
    final session = _pendingSession;
    if (session == null) {
      return;
    }
    widget.onSignedIn(session);
  }

  void _showIntro() {
    setState(() {
      _loginStep = 1;
    });
  }

  void _showLoginForm() {
    setState(() {
      _isRegistering = false;
      _authError = null;
      _loginStep = 2;
    });
  }

  void _showRegisterForm() {
    setState(() {
      _isRegistering = true;
      _authError = null;
      _loginStep = 2;
    });
  }

  void _showSignInForm() {
    setState(() {
      _isRegistering = false;
      _authError = null;
    });
  }

  void _showWelcome() {
    setState(() {
      _loginStep = 0;
    });
  }

  bool _isRussian(AppLocalizations l10n) => l10n.locale.languageCode == 'ru';

  String _welcomeTitle(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Добро пожаловать' : 'Welcome';

  String _welcomeSubtitle(AppLocalizations l10n) => _isRussian(l10n)
      ? 'Сначала выберите, как зайти в библиотеку. После этого откроются ваши книги, манга, манхва и настройки чтения.'
      : 'Choose how to enter the library first. After that you can open books, manga, manhwa, and reading settings.';

  String _startLabel(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Войти в профиль' : 'Enter profile';

  String _backLabel(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Назад' : 'Back';

  String _nextLabel(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Р”Р°Р»СЊС€Рµ' : 'Next';

  String _introTitle(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'Р§С‚Рѕ РІР°СЃ Р¶РґС‘С‚' : 'What awaits you';

  String _introSubtitle(AppLocalizations l10n) => _isRussian(l10n)
      ? 'РџСЂРёР»РѕР¶РµРЅРёРµ СЃРѕР±РёСЂР°РµС‚ РІ РѕРґРЅРѕРј РјРµСЃС‚Рµ EPUB, РјР°РЅРіСѓ Рё РјР°РЅС…РІСѓ, Р° РїРѕР·Р¶Рµ СЃСЋРґР° РјРѕР¶РЅРѕ Р±СѓРґРµС‚ РїРѕРґРєР»СЋС‡РёС‚СЊ РІР°С€ Р±СЌРєРµРЅРґ.'
      : 'The app brings EPUB, manga, and manhwa into one library, and later you can connect your backend here.';

  String _thanksTitle(AppLocalizations l10n, ReaderUserSession? session) {
    if (session?.isGuest == true) {
      return _isRussian(l10n)
          ? 'РЎРїР°СЃРёР±Рѕ Р·Р° РІС‹Р±РѕСЂ'
          : 'Thanks for choosing us';
    }
    return _isRussian(l10n)
        ? 'РЎРїР°СЃРёР±Рѕ Р·Р° СЂРµРіРёСЃС‚СЂР°С†РёСЋ'
        : 'Thanks for signing in';
  }

  String _thanksSubtitle(AppLocalizations l10n, ReaderUserSession? session) {
    if (session?.isGuest == true) {
      return _isRussian(l10n)
          ? 'Р“РѕСЃС‚РµРІРѕР№ РІС…РѕРґ РіРѕС‚РѕРІ. РЎРїР°СЃРёР±Рѕ, С‡С‚Рѕ РІС‹Р±СЂР°Р»Рё РЅР°С€Рµ РїСЂРёР»РѕР¶РµРЅРёРµ.'
          : 'Guest mode is ready. Thank you for choosing our app.';
    }
    return _isRussian(l10n)
        ? 'Р’С…РѕРґ РіРѕС‚РѕРІ. РЎРїР°СЃРёР±Рѕ, С‡С‚Рѕ Р·Р°СЂРµРіРёСЃС‚СЂРёСЂРѕРІР°Р»РёСЃСЊ Рё РІС‹Р±СЂР°Р»Рё РЅР°С€Сѓ Р±РёР±Р»РёРѕС‚РµРєСѓ.'
        : 'Your login is ready. Thank you for registering and choosing our library.';
  }

  String _openLibraryLabel(AppLocalizations l10n) =>
      _isRussian(l10n) ? 'РћС‚РєСЂС‹С‚СЊ Р±РёР±Р»РёРѕС‚РµРєСѓ' : 'Open library';

  String _welcomeTitleText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0414\u043e\u0431\u0440\u043e \u043f\u043e\u0436\u0430\u043b\u043e\u0432\u0430\u0442\u044c'
      : 'Welcome';

  String _welcomeSubtitleText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u042d\u0442\u043e \u0432\u0430\u0448\u0430 \u0446\u0438\u0444\u0440\u043e\u0432\u0430\u044f \u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0430. \u041f\u0440\u043e\u0439\u0434\u0438\u0442\u0435 \u043a\u043e\u0440\u043e\u0442\u043a\u043e\u0435 \u0437\u043d\u0430\u043a\u043e\u043c\u0441\u0442\u0432\u043e, \u0430 \u043f\u043e\u0442\u043e\u043c \u0432\u043e\u0439\u0434\u0438\u0442\u0435 \u0432 \u043f\u0440\u043e\u0444\u0438\u043b\u044c.'
      : 'This is your digital library. Take a short tour first, then sign in to your profile.';

  String _nextText(AppLocalizations l10n) =>
      _isRussian(l10n) ? '\u0414\u0430\u043b\u044c\u0448\u0435' : 'Next';

  String _backText(AppLocalizations l10n) =>
      _isRussian(l10n) ? '\u041d\u0430\u0437\u0430\u0434' : 'Back';

  String _introTitleText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0427\u0442\u043e \u0432\u0430\u0441 \u0436\u0434\u0435\u0442'
      : 'What awaits you';

  String _introSubtitleText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u041f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u0441\u043e\u0431\u0438\u0440\u0430\u0435\u0442 EPUB, \u043c\u0430\u043d\u0433\u0443 \u0438 \u043c\u0430\u043d\u0445\u0432\u0443 \u0432 \u043e\u0434\u043d\u043e\u043c \u043c\u0435\u0441\u0442\u0435. \u041f\u043e\u0437\u0436\u0435 \u0441\u044e\u0434\u0430 \u043c\u043e\u0436\u043d\u043e \u0431\u0443\u0434\u0435\u0442 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0432\u0430\u0448 \u0431\u044d\u043a\u0435\u043d\u0434.'
      : 'The app brings EPUB, manga, and manhwa into one library. Later you can connect your backend here.';

  String _thanksTitleText(AppLocalizations l10n, ReaderUserSession? session) {
    if (session?.isGuest == true) {
      return _isRussian(l10n)
          ? '\u0421\u043f\u0430\u0441\u0438\u0431\u043e \u0437\u0430 \u0432\u044b\u0431\u043e\u0440'
          : 'Thanks for choosing us';
    }
    return _isRussian(l10n)
        ? '\u0421\u043f\u0430\u0441\u0438\u0431\u043e \u0437\u0430 \u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044e'
        : 'Thanks for signing in';
  }

  String _thanksSubtitleText(
    AppLocalizations l10n,
    ReaderUserSession? session,
  ) {
    if (session?.isGuest == true) {
      return _isRussian(l10n)
          ? '\u0413\u043e\u0441\u0442\u0435\u0432\u043e\u0439 \u0432\u0445\u043e\u0434 \u0433\u043e\u0442\u043e\u0432. \u0421\u043f\u0430\u0441\u0438\u0431\u043e, \u0447\u0442\u043e \u0432\u044b\u0431\u0440\u0430\u043b\u0438 \u043d\u0430\u0448\u0435 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435.'
          : 'Guest mode is ready. Thank you for choosing our app.';
    }
    return _isRussian(l10n)
        ? '\u0412\u0445\u043e\u0434 \u0433\u043e\u0442\u043e\u0432. \u0421\u043f\u0430\u0441\u0438\u0431\u043e, \u0447\u0442\u043e \u0437\u0430\u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0438\u0440\u043e\u0432\u0430\u043b\u0438\u0441\u044c \u0438 \u0432\u044b\u0431\u0440\u0430\u043b\u0438 \u043d\u0430\u0448\u0443 \u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0443.'
        : 'Your login is ready. Thank you for registering and choosing our library.';
  }

  String _openLibraryText(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u041e\u0442\u043a\u0440\u044b\u0442\u044c \u0431\u0438\u0431\u043b\u0438\u043e\u0442\u0435\u043a\u0443'
      : 'Open library';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Stack(
        children: [
          _LoginBackdrop(palette: _palette),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 860;
                final horizontalPadding = isCompact ? 16.0 : 28.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    18,
                    horizontalPadding,
                    30,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: Column(
                        children: [
                          _LoginTopBar(
                            palette: _palette,
                            themeChoice: widget.themeChoice,
                            languageChoice: widget.languageChoice,
                            onThemeChanged: widget.onThemeChanged,
                            onLanguageChanged: widget.onLanguageChanged,
                          ),
                          SizedBox(height: isCompact ? 18 : 26),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 360),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.04, 0),
                                    end: Offset.zero,
                                  ).animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: _loginStep == 0
                                ? _LoginWelcomeStage(
                                    key: const ValueKey('login-welcome'),
                                    palette: _palette,
                                    title: _welcomeTitleText(l10n),
                                    subtitle: _welcomeSubtitleText(l10n),
                                    startLabel: _nextText(l10n),
                                    guestLabel: l10n.continueAsGuest,
                                    featureLabels: [
                                      l10n.builtInLibraries,
                                      l10n.featureThemes,
                                      l10n.featureToc,
                                    ],
                                    onStart: _showIntro,
                                    onContinueAsGuest: _continueAsGuest,
                                  )
                                : _loginStep == 1
                                ? _LoginIntroStage(
                                    key: const ValueKey('login-intro'),
                                    palette: _palette,
                                    title: _introTitleText(l10n),
                                    subtitle: _introSubtitleText(l10n),
                                    nextLabel: _nextText(l10n),
                                    backLabel: _backText(l10n),
                                    features: [
                                      _IntroFeatureData(
                                        icon: Icons.menu_book_rounded,
                                        title: l10n.epubReaderTitle,
                                        subtitle: l10n.featureImages,
                                      ),
                                      _IntroFeatureData(
                                        icon:
                                            Icons.collections_bookmark_rounded,
                                        title: l10n.manhwaReader,
                                        subtitle: l10n.featureToc,
                                      ),
                                      _IntroFeatureData(
                                        icon: Icons.photo_library_rounded,
                                        title: l10n.mangaReader,
                                        subtitle: l10n.featureThemes,
                                      ),
                                    ],
                                    onBack: _showWelcome,
                                    onNext: _showLoginForm,
                                  )
                                : _loginStep == 3
                                ? _LoginThanksStage(
                                    key: const ValueKey('login-thanks'),
                                    palette: _palette,
                                    title: _thanksTitleText(
                                      l10n,
                                      _pendingSession,
                                    ),
                                    subtitle: _thanksSubtitleText(
                                      l10n,
                                      _pendingSession,
                                    ),
                                    actionLabel: _openLibraryText(l10n),
                                    onFinish: _finishLogin,
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('login-form'),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: isCompact ? 640 : 520,
                                        ),
                                        child: _LoginCard(
                                          palette: _palette,
                                          formKey: _formKey,
                                          isRegistering: _isRegistering,
                                          nameController: _nameController,
                                          phoneController: _phoneController,
                                          emailController: _emailController,
                                          passwordController:
                                              _passwordController,
                                          obscurePassword: _obscurePassword,
                                          isSubmitting: _isSubmitting,
                                          errorMessage: _authError,
                                          backLabel: _backText(l10n),
                                          onBack: _showIntro,
                                          onTogglePassword: () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                          onSubmit: _submit,
                                          onRegister: _showRegisterForm,
                                          onSignInMode: _showSignInForm,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final isDark = palette.brightness == Brightness.dark;
    final mutedLine = palette.divider.withValues(alpha: isDark ? 0.7 : 0.9);

    return ColoredBox(
      color: palette.appBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.appBackground,
                    palette.panelBackground.withValues(alpha: 0.72),
                    palette.appBackground,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            left: -44,
            right: -44,
            top: 104,
            child: _BackdropShelf(
              palette: palette,
              lineColor: mutedLine,
              bookColors: [
                palette.accent,
                const Color(0xFF2E8B78),
                const Color(0xFFD46844),
                palette.titleColor.withValues(alpha: 0.72),
              ],
            ),
          ),
          Positioned(
            left: -70,
            right: -70,
            bottom: 96,
            child: Transform.rotate(
              angle: -0.035,
              child: _BackdropShelf(
                palette: palette,
                lineColor: mutedLine,
                bookColors: [
                  const Color(0xFF6D7FD9),
                  palette.accent,
                  const Color(0xFFB85C5C),
                  const Color(0xFF2E8B78),
                ],
              ),
            ),
          ),
          Positioned(
            right: -32,
            top: 230,
            child: Transform.rotate(
              angle: 0.14,
              child: _LooseBookStack(palette: palette),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropShelf extends StatelessWidget {
  const _BackdropShelf({
    required this.palette,
    required this.lineColor,
    required this.bookColors,
  });

  final ReaderPalette palette;
  final Color lineColor;
  final List<Color> bookColors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 11,
            child: Container(height: 2, color: lineColor),
          ),
          Positioned(
            left: 70,
            bottom: 13,
            child: Opacity(
              opacity: 0.18,
              child: Row(
                children: [
                  for (var index = 0; index < 13; index++) ...[
                    _BookSpine(
                      color: bookColors[index % bookColors.length],
                      width: 10 + ((index % 4) * 3),
                      height: 34 + ((index % 5) * 7),
                      lean: (index.isEven ? -1 : 1) * 0.025,
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LooseBookStack extends StatelessWidget {
  const _LooseBookStack({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BookCoverPlate(width: 124, height: 16, color: palette.accent),
          const SizedBox(height: 8),
          _BookCoverPlate(
            width: 164,
            height: 18,
            color: const Color(0xFF2E8B78),
          ),
          const SizedBox(height: 8),
          _BookCoverPlate(
            width: 138,
            height: 16,
            color: const Color(0xFFD46844),
          ),
        ],
      ),
    );
  }
}

class _BookCoverPlate extends StatelessWidget {
  const _BookCoverPlate({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _BookSpine extends StatelessWidget {
  const _BookSpine({
    required this.color,
    required this.width,
    required this.height,
    this.lean = 0,
  });

  final Color color;
  final double width;
  final double height;
  final double lean;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: lean,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _LoginTopBar extends StatelessWidget {
  const _LoginTopBar({
    required this.palette,
    required this.themeChoice,
    required this.languageChoice,
    required this.onThemeChanged,
    required this.onLanguageChanged,
  });

  final ReaderPalette palette;
  final ReaderThemeChoice themeChoice;
  final AppLanguage languageChoice;
  final ValueChanged<ReaderThemeChoice> onThemeChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LoginTopBarMenu<ReaderThemeChoice>(
          tooltip: l10n.theme,
          icon: themeChoice.icon,
          palette: palette,
          onSelected: onThemeChanged,
          itemBuilder: (context) => [
            for (final choice in ReaderThemeChoice.values)
              PopupMenuItem(value: choice, child: Text(choice.label(l10n))),
          ],
        ),
        const SizedBox(width: 6),
        _LoginTopBarMenu<AppLanguage>(
          tooltip: l10n.language,
          icon: Icons.language_rounded,
          palette: palette,
          onSelected: onLanguageChanged,
          itemBuilder: (context) => [
            for (final choice in AppLanguage.values)
              PopupMenuItem(value: choice, child: Text(choice.label(l10n))),
          ],
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.local_library_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.titleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              controls,
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginTopBarMenu<T> extends StatelessWidget {
  const _LoginTopBarMenu({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String tooltip;
  final IconData icon;
  final ReaderPalette palette;
  final ValueChanged<T> onSelected;
  final PopupMenuItemBuilder<T> itemBuilder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        onSelected: onSelected,
        padding: EdgeInsets.zero,
        itemBuilder: itemBuilder,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: palette.accent, size: 20),
        ),
      ),
    );
  }
}

class _IntroFeatureData {
  const _IntroFeatureData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _LoginIntroStage extends StatelessWidget {
  const _LoginIntroStage({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.nextLabel,
    required this.backLabel,
    required this.features,
    required this.onBack,
    required this.onNext,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String nextLabel;
  final String backLabel;
  final List<_IntroFeatureData> features;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Icon(Icons.explore_rounded, color: palette.accent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: palette.titleColor,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: palette.bodyColor,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final useRow = constraints.maxWidth >= 760;
                if (!useRow) {
                  return Column(
                    children: [
                      for (var index = 0; index < features.length; index++) ...[
                        _IntroFeatureCard(
                          palette: palette,
                          data: features[index],
                          index: index + 1,
                        ),
                        if (index != features.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    for (var index = 0; index < features.length; index++) ...[
                      Expanded(
                        child: _IntroFeatureCard(
                          palette: palette,
                          data: features[index],
                          index: index + 1,
                        ),
                      ),
                      if (index != features.length - 1)
                        const SizedBox(width: 12),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _StageNavigation(
              backLabel: backLabel,
              nextLabel: nextLabel,
              onBack: onBack,
              onNext: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroFeatureCard extends StatelessWidget {
  const _IntroFeatureCard({
    required this.palette,
    required this.data,
    required this.index,
  });

  final ReaderPalette palette;
  final _IntroFeatureData data;
  final int index;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(data.icon, color: palette.accent),
                  ),
                ),
                const Spacer(),
                Text(
                  '0$index',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.titleColor.withValues(alpha: 0.18),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: palette.titleColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.mutedColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginThanksStage extends StatelessWidget {
  const _LoginThanksStage({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onFinish,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    Icons.verified_rounded,
                    color: palette.accent,
                    size: 44,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: palette.titleColor,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.bodyColor,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            _LoginPerforationLine(palette: palette),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.local_library_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageNavigation extends StatelessWidget {
  const _StageNavigation({
    required this.backLabel,
    required this.nextLabel,
    required this.onBack,
    required this.onNext,
  });

  final String backLabel;
  final String nextLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 420;
        final backButton = OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(backLabel),
        );
        final nextButton = FilledButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(nextLabel),
        );

        if (!useRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [nextButton, const SizedBox(height: 10), backButton],
          );
        }

        return Row(
          children: [
            Expanded(child: backButton),
            const SizedBox(width: 10),
            Expanded(child: nextButton),
          ],
        );
      },
    );
  }
}

class _LoginWelcomeStage extends StatelessWidget {
  const _LoginWelcomeStage({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.startLabel,
    required this.guestLabel,
    required this.featureLabels,
    required this.onStart,
    required this.onContinueAsGuest,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String startLabel;
  final String guestLabel;
  final List<String> featureLabels;
  final VoidCallback onStart;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final compactPortal = constraints.maxWidth < 980;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.panelBackground.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 38,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 20 : 30,
              isCompact ? 22 : 30,
              isCompact ? 20 : 30,
              isCompact ? 20 : 30,
            ),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WelcomeCopy(
                        palette: palette,
                        title: title,
                        subtitle: subtitle,
                        featureLabels: featureLabels,
                      ),
                      const SizedBox(height: 24),
                      _WelcomePortal(palette: palette, compact: true),
                      const SizedBox(height: 22),
                      _WelcomeActions(
                        startLabel: startLabel,
                        guestLabel: guestLabel,
                        onStart: onStart,
                        onContinueAsGuest: onContinueAsGuest,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: _WelcomeCopy(
                          palette: palette,
                          title: title,
                          subtitle: subtitle,
                          featureLabels: featureLabels,
                        ),
                      ),
                      const SizedBox(width: 34),
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            _WelcomePortal(
                              palette: palette,
                              compact: compactPortal,
                            ),
                            const SizedBox(height: 22),
                            _WelcomeActions(
                              startLabel: startLabel,
                              guestLabel: guestLabel,
                              onStart: onStart,
                              onContinueAsGuest: onContinueAsGuest,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _WelcomeCopy extends StatelessWidget {
  const _WelcomeCopy({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.featureLabels,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final List<String> featureLabels;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  color: palette.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).appTitle,
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: isCompact ? 38 : 50,
            color: palette.titleColor,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: palette.bodyColor,
              height: 1.48,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final label in featureLabels)
              _LoginFeatureChip(label: label, palette: palette),
          ],
        ),
      ],
    );
  }
}

class _WelcomePortal extends StatelessWidget {
  const _WelcomePortal({required this.palette, required this.compact});

  final ReaderPalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 18),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.pageBackground.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.divider),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 22,
            compact ? 18 : 22,
            compact ? 18 : 22,
            compact ? 16 : 20,
          ),
          child: Column(
            children: [
              _LoginBookPortal(palette: palette, compact: compact),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _WelcomeStepBadge(
                      palette: palette,
                      icon: Icons.person_rounded,
                      label: '1',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WelcomeStepBadge(
                      palette: palette,
                      icon: Icons.library_books_rounded,
                      label: '2',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WelcomeStepBadge(
                      palette: palette,
                      icon: Icons.auto_stories_rounded,
                      label: '3',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _WelcomeStepBadge(
                      palette: palette,
                      icon: Icons.verified_rounded,
                      label: '4',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeStepBadge extends StatelessWidget {
  const _WelcomeStepBadge({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: palette.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.titleColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  const _WelcomeActions({
    required this.startLabel,
    required this.guestLabel,
    required this.onStart,
    required this.onContinueAsGuest,
  });

  final String startLabel;
  final String guestLabel;
  final VoidCallback onStart;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 500;
        final startButton = FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(startLabel),
        );
        final guestButton = OutlinedButton.icon(
          onPressed: onContinueAsGuest,
          icon: const Icon(Icons.person_outline_rounded),
          label: Text(guestLabel),
        );

        if (!useRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [startButton, const SizedBox(height: 10), guestButton],
          );
        }

        return Row(
          children: [
            Expanded(child: startButton),
            const SizedBox(width: 10),
            Expanded(child: guestButton),
          ],
        );
      },
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.featureLabels,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final List<String> featureLabels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.panelBackground.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: isNarrow ? 18 : 30,
                top: isNarrow ? 18 : 28,
                child: _LoginSeal(palette: palette),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 20 : 28,
                  isNarrow ? 76 : 30,
                  isNarrow ? 20 : 28,
                  isNarrow ? 22 : 28,
                ),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LoginHeroCopy(
                            palette: palette,
                            title: title,
                            subtitle: subtitle,
                            featureLabels: featureLabels,
                          ),
                          const SizedBox(height: 22),
                          _LoginBookPortal(palette: palette, compact: true),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _LoginHeroCopy(
                              palette: palette,
                              title: title,
                              subtitle: subtitle,
                              featureLabels: featureLabels,
                            ),
                          ),
                          const SizedBox(width: 26),
                          Expanded(
                            flex: 4,
                            child: _LoginBookPortal(
                              palette: palette,
                              compact: false,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoginHeroCopy extends StatelessWidget {
  const _LoginHeroCopy({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.featureLabels,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final List<String> featureLabels;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isCompact = MediaQuery.sizeOf(context).width < 430;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded, color: palette.accent),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context).accountStatusLocal,
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: textTheme.headlineMedium?.copyWith(
            fontSize: isCompact ? 31 : 42,
            fontWeight: FontWeight.w900,
            height: 1.02,
            color: palette.titleColor,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            subtitle,
            style: textTheme.bodyLarge?.copyWith(
              color: palette.bodyColor,
              height: 1.48,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final label in featureLabels)
              _LoginFeatureChip(label: label, palette: palette),
          ],
        ),
      ],
    );
  }
}

class _LoginSeal extends StatelessWidget {
  const _LoginSeal({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Icon(Icons.verified_rounded, color: palette.accent, size: 24),
      ),
    );
  }
}

class _LoginBookPortal extends StatelessWidget {
  const _LoginBookPortal({required this.palette, required this.compact});

  final ReaderPalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 166.0 : 260.0;
    final bookCount = compact ? 7 : 11;
    final spineColors = [
      palette.accent,
      const Color(0xFF2E8B78),
      const Color(0xFFD46844),
      const Color(0xFF6D7FD9),
      palette.titleColor.withValues(alpha: 0.72),
    ];

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: compact ? 18 : 24,
              decoration: BoxDecoration(
                color: palette.titleColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.divider),
              ),
            ),
          ),
          Positioned(
            left: compact ? 16 : 26,
            right: compact ? 16 : 26,
            bottom: compact ? 16 : 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < bookCount; index++) ...[
                  _BookSpine(
                    color: spineColors[index % spineColors.length],
                    width: compact
                        ? 13 + (index % 3) * 4
                        : 16 + (index % 3) * 6,
                    height: compact
                        ? 74 + (index % 5) * 12
                        : 126 + (index % 5) * 18,
                    lean: index == 2
                        ? -0.08
                        : index == 8
                        ? 0.07
                        : 0,
                  ),
                  if (index != bookCount - 1) SizedBox(width: compact ? 6 : 9),
                ],
              ],
            ),
          ),
          Positioned(
            right: compact ? 12 : 26,
            top: compact ? 8 : 18,
            child: _LoginMiniTicket(
              palette: palette,
              icon: Icons.bookmark_added_rounded,
              label: AppLocalizations.of(context).builtInLibraries,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginMiniTicket extends StatelessWidget {
  const _LoginMiniTicket({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: palette.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 124),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.bodyColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.palette,
    required this.formKey,
    required this.isRegistering,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isSubmitting,
    required this.errorMessage,
    required this.backLabel,
    required this.onBack,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onRegister,
    required this.onSignInMode,
  });

  final ReaderPalette palette;
  final GlobalKey<FormState> formKey;
  final bool isRegistering;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isSubmitting;
  final String? errorMessage;
  final String backLabel;
  final VoidCallback onBack;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;
  final VoidCallback onSignInMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 26),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panelBackground.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: palette.divider),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 36,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 9, color: palette.accent),
              ),
              Positioned(
                right: -34,
                top: 34,
                child: Transform.rotate(
                  angle: 0.12,
                  child: Icon(
                    Icons.local_library_rounded,
                    size: 128,
                    color: palette.accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 24, 22, 22),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LoginCardHeader(
                        palette: palette,
                        title: _cardTitle(l10n),
                        backLabel: backLabel,
                        onBack: onBack,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _cardHint(l10n),
                        style: TextStyle(
                          color: palette.mutedColor,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _LoginPerforationLine(palette: palette),
                      const SizedBox(height: 18),
                      if (isRegistering) ...[
                        TextFormField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              _validateNameForCard(value, l10n),
                          decoration: InputDecoration(
                            labelText: _usernameLabel(l10n),
                            prefixIcon: const Icon(Icons.badge_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            _validatePhoneForCard(value, l10n),
                        decoration: InputDecoration(
                          labelText: l10n.phoneNumber,
                          prefixIcon: const Icon(Icons.call_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (isRegistering) ...[
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              _validateEmailForCard(value, l10n),
                          decoration: InputDecoration(
                            labelText: l10n.emailAddress,
                            prefixIcon: const Icon(
                              Icons.alternate_email_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: (value) =>
                            _validatePasswordForCard(value, l10n),
                        onFieldSubmitted: (_) => onSubmit(),
                        decoration: InputDecoration(
                          labelText: l10n.password,
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            onPressed: onTogglePassword,
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _LoginErrorMessage(
                          palette: palette,
                          message: errorMessage!,
                        ),
                      ],
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final useRow = constraints.maxWidth >= 460;
                          final primaryButton = FilledButton.icon(
                            onPressed: isSubmitting ? null : onSubmit,
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    isRegistering
                                        ? Icons.how_to_reg_rounded
                                        : Icons.login_rounded,
                                  ),
                            label: Text(
                              isRegistering
                                  ? _createAccountLabel(l10n)
                                  : l10n.signIn,
                            ),
                          );
                          final secondaryButton = OutlinedButton.icon(
                            onPressed: isSubmitting
                                ? null
                                : isRegistering
                                ? onSignInMode
                                : onRegister,
                            icon: Icon(
                              isRegistering
                                  ? Icons.login_rounded
                                  : Icons.person_add_alt_rounded,
                            ),
                            label: Text(
                              isRegistering
                                  ? _signInModeLabel(l10n)
                                  : _registerLabel(l10n),
                            ),
                          );

                          if (!useRow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                primaryButton,
                                const SizedBox(height: 10),
                                secondaryButton,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: primaryButton),
                              const SizedBox(width: 10),
                              Expanded(child: secondaryButton),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isRussian(AppLocalizations l10n) => l10n.locale.languageCode == 'ru';

  String _cardTitle(AppLocalizations l10n) => isRegistering
      ? (_isRussian(l10n)
            ? '\u0420\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044f'
            : 'Register')
      : l10n.signIn;

  String _cardHint(AppLocalizations l10n) {
    if (!isRegistering) {
      return l10n.localProfileHint;
    }
    return _isRussian(l10n)
        ? '\u0421\u043e\u0437\u0434\u0430\u0439\u0442\u0435 \u043b\u043e\u043a\u0430\u043b\u044c\u043d\u044b\u0439 \u043f\u0440\u043e\u0444\u0438\u043b\u044c: \u0438\u043c\u044f, \u043d\u043e\u043c\u0435\u0440, email \u0438 \u043f\u0430\u0440\u043e\u043b\u044c.'
        : 'Create a local profile with username, phone number, email, and password.';
  }

  String _usernameLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f'
      : 'Username';

  String _registerLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0420\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044f'
      : 'Register';

  String _createAccountLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0417\u0430\u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0438\u0440\u043e\u0432\u0430\u0442\u044c\u0441\u044f'
      : 'Create account';

  String _signInModeLabel(AppLocalizations l10n) =>
      _isRussian(l10n) ? '\u0412\u0445\u043e\u0434' : 'Sign in';

  String? _validateNameForCard(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _isRussian(l10n)
          ? '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0438\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f'
          : 'Enter a username';
    }
    if (trimmed.length < 2) {
      return _isRussian(l10n)
          ? '\u0418\u043c\u044f \u0441\u043b\u0438\u0448\u043a\u043e\u043c \u043a\u043e\u0440\u043e\u0442\u043a\u043e\u0435'
          : 'Username is too short';
    }
    return null;
  }

  String? _validatePhoneForCard(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.phoneRequired;
    }
    final normalized = trimmed.replaceAll(RegExp(r'[\s()+-]'), '');
    final isNumeric = RegExp(r'^\d+$').hasMatch(normalized);
    if (!isNumeric || normalized.length < 7) {
      return l10n.invalidPhone;
    }
    return null;
  }

  String? _validateEmailForCard(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.emailRequired;
    }
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
    if (!isValid) {
      return l10n.invalidEmail;
    }
    return null;
  }

  String? _validatePasswordForCard(String? value, AppLocalizations l10n) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return l10n.passwordRequired;
    }
    if (trimmed.length < 4) {
      return l10n.passwordTooShort;
    }
    return null;
  }
}

class _LoginErrorMessage extends StatelessWidget {
  const _LoginErrorMessage({required this.palette, required this.message});

  final ReaderPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: palette.bodyColor, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCardHeader extends StatelessWidget {
  const _LoginCardHeader({
    required this.palette,
    required this.title,
    required this.backLabel,
    required this.onBack,
  });

  final ReaderPalette palette;
  final String title;
  final String backLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(
              Icons.confirmation_number_rounded,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: palette.titleColor,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).accountStatusLocal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.mutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.pageBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.divider),
          ),
          child: Tooltip(
            message: backLabel,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_rounded,
                color: palette.accent,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginPerforationLine extends StatelessWidget {
  const _LoginPerforationLine({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < 18; index++) ...[
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: index.isEven
                    ? palette.divider
                    : palette.divider.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (index != 17) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _LoginFeatureChip extends StatelessWidget {
  const _LoginFeatureChip({required this.label, required this.palette});

  final String label;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: palette.accent),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.bodyColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
