import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'reader_theme.dart';
import 'reader_user_session.dart';

class ReaderProfilePage extends StatefulWidget {
  const ReaderProfilePage({
    super.key,
    required this.palette,
    required this.user,
    required this.themeChoice,
    required this.languageChoice,
    required this.totalTitles,
    required this.totalChapters,
    required this.totalFormats,
    required this.activeBookTitle,
    required this.activeChapterTitle,
    required this.onThemeTap,
    required this.onLanguageTap,
    required this.onUserChanged,
    required this.onSignOut,
  });

  final ReaderPalette palette;
  final ReaderUserSession user;
  final ReaderThemeChoice themeChoice;
  final AppLanguage languageChoice;
  final int totalTitles;
  final int totalChapters;
  final int totalFormats;
  final String? activeBookTitle;
  final String? activeChapterTitle;
  final VoidCallback onThemeTap;
  final VoidCallback onLanguageTap;
  final ValueChanged<ReaderUserSession> onUserChanged;
  final VoidCallback onSignOut;

  @override
  State<ReaderProfilePage> createState() => _ReaderProfilePageState();
}

class _ReaderProfilePageState extends State<ReaderProfilePage> {
  late ReaderUserSession _user;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  String _userLabel(AppLocalizations l10n) {
    if (_user.isGuest) {
      return l10n.guestUser;
    }

    final name = _user.displayName.trim();
    return name.isEmpty ? _unnamedUserLabel(l10n) : name;
  }

  String _unnamedUserLabel(AppLocalizations l10n) =>
      l10n.locale.languageCode == 'ru'
      ? '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c'
      : 'User';

  String _userSubtitle(AppLocalizations l10n) => _user.isGuest
      ? l10n.accountStatusLocal
      : (_user.email.trim().isNotEmpty
            ? _user.email.trim()
            : l10n.accountStatusLocal);

  String _userEmail(AppLocalizations l10n) => _user.email.trim().isEmpty
      ? l10n.emailNotSet
      : _user.email.trim();

  String _userPhone(AppLocalizations l10n) => _user.phoneNumber.trim().isEmpty
      ? l10n.phoneNotSet
      : _user.phoneNumber.trim();

  bool _isRussian(AppLocalizations l10n) => l10n.locale.languageCode == 'ru';

  String _usernameLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0418\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f'
      : 'Username';

  String _usernameRequiredLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0438\u043c\u044f \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f'
      : 'Enter a username';

  String _usernameTooShortLabel(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0418\u043c\u044f \u0441\u043b\u0438\u0448\u043a\u043e\u043c \u043a\u043e\u0440\u043e\u0442\u043a\u043e\u0435'
      : 'Username is too short';

  String _editContactsSubtitle(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0418\u043c\u044f, email \u0438 \u043d\u043e\u043c\u0435\u0440 \u0442\u0435\u043b\u0435\u0444\u043e\u043d\u0430'
      : 'Name, email, and phone number';

  String _signOutSubtitle(AppLocalizations l10n) => _isRussian(l10n)
      ? '\u0412\u044b\u0439\u0442\u0438 \u0438\u0437 \u044d\u0442\u043e\u0433\u043e \u043f\u0440\u043e\u0444\u0438\u043b\u044f'
      : 'Leave this profile';

  String _initials(AppLocalizations l10n) {
    final source = _userLabel(l10n).trim();
    if (source.isEmpty) {
      return 'R';
    }

    final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final firstTwo = parts.take(2).toList();
    if (firstTwo.isEmpty) {
      return source.substring(0, 1).toUpperCase();
    }

    return firstTwo.map((part) => part.substring(0, 1).toUpperCase()).join();
  }

  Future<void> _editContacts() async {
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _user.displayName);
    final emailController = TextEditingController(text: _user.email);
    final phoneController = TextEditingController(text: _user.phoneNumber);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: widget.palette.panelBackground,
        builder: (sheetContext) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.editContacts,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: widget.palette.titleColor,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: _usernameLabel(l10n),
                      prefixIcon: const Icon(Icons.badge_rounded),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (!_user.isGuest && trimmed.isEmpty) {
                        return _usernameRequiredLabel(l10n);
                      }
                      if (trimmed.isNotEmpty && trimmed.length < 2) {
                        return _usernameTooShortLabel(l10n);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.emailAddress,
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return _user.isGuest ? null : l10n.emailRequired;
                      }
                      if (!trimmed.contains('@') || !trimmed.contains('.')) {
                        return l10n.invalidEmail;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.phoneNumber,
                      prefixIcon: const Icon(Icons.call_rounded),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return null;
                      }
                      final normalized = trimmed.replaceAll(
                        RegExp(r'[\s()+-]'),
                        '',
                      );
                      final isNumeric = RegExp(r'^\d+$').hasMatch(normalized);
                      if (!isNumeric || normalized.length < 7) {
                        return l10n.invalidPhone;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(l10n.cancelAction),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) {
                            return;
                          }

                          final updatedUser = _user.copyWith(
                            displayName: nameController.text.trim(),
                            email: emailController.text.trim(),
                            phoneNumber: phoneController.text.trim(),
                          );
                          setState(() {
                            _user = updatedUser;
                          });
                          widget.onUserChanged(updatedUser);
                          Navigator.of(sheetContext).pop();
                        },
                        child: Text(l10n.saveChanges),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      nameController.dispose();
      emailController.dispose();
      phoneController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final userLabel = _userLabel(l10n);
    final userSubtitle = _userSubtitle(l10n);
    final contactColumns = MediaQuery.sizeOf(context).width >= 980
        ? 3
        : MediaQuery.sizeOf(context).width >= 620
        ? 2
        : 1;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountSection)),
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: _ProfileOrb(
              size: 220,
              color: widget.palette.accent.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            left: -60,
            top: 200,
            child: _ProfileOrb(
              size: 170,
              color: widget.palette.titleColor.withValues(alpha: 0.05),
            ),
          ),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 760;
                      final veryCompact = constraints.maxWidth < 430;
                      final actionColumns = constraints.maxWidth >= 980
                          ? 3
                          : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                      const gap = 12.0;
                      final actionWidth =
                          (constraints.maxWidth - ((actionColumns - 1) * gap)) /
                          actionColumns;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ProfileHero(
                            palette: widget.palette,
                            compact: compact,
                            veryCompact: veryCompact,
                            initials: _initials(l10n),
                            title: l10n.welcomeUser(userLabel),
                            subtitle: userSubtitle,
                            description: l10n.libraryIntroSubtitle,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            l10n.contactInfo,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: widget.palette.titleColor,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              _ProfileContactCard(
                                width:
                                    (constraints.maxWidth -
                                            ((contactColumns - 1) * gap)) /
                                        contactColumns,
                                palette: widget.palette,
                                icon: Icons.alternate_email_rounded,
                                label: l10n.emailAddress,
                                value: _userEmail(l10n),
                              ),
                              _ProfileContactCard(
                                width:
                                    (constraints.maxWidth -
                                            ((contactColumns - 1) * gap)) /
                                        contactColumns,
                                palette: widget.palette,
                                icon: Icons.call_rounded,
                                label: l10n.phoneNumber,
                                value: _userPhone(l10n),
                              ),
                              _ProfileActionCard(
                                width:
                                    (constraints.maxWidth -
                                            ((contactColumns - 1) * gap)) /
                                        contactColumns,
                                palette: widget.palette,
                                icon: Icons.edit_rounded,
                                title: l10n.editContacts,
                                subtitle: _editContactsSubtitle(l10n),
                                accent: widget.palette.accent,
                                onTap: _editContacts,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.appearanceSection,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: widget.palette.titleColor,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              _ProfileActionCard(
                                width: actionWidth,
                                palette: widget.palette,
                                icon: widget.themeChoice.icon,
                                title: l10n.theme,
                                subtitle: widget.themeChoice.label(l10n),
                                accent: widget.palette.accent,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onThemeTap();
                                },
                              ),
                              _ProfileActionCard(
                                width: actionWidth,
                                palette: widget.palette,
                                icon: Icons.language_rounded,
                                title: l10n.language,
                                subtitle: widget.languageChoice.label(l10n),
                                accent: widget.palette.accent,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onLanguageTap();
                                },
                              ),
                              _ProfileActionCard(
                                width: actionWidth,
                                palette: widget.palette,
                                icon: Icons.logout_rounded,
                                title: l10n.signOut,
                                subtitle: _signOutSubtitle(l10n),
                                accent: const Color(0xFFD46844),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onSignOut();
                                },
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.palette,
    required this.compact,
    required this.veryCompact,
    required this.initials,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  final ReaderPalette palette;
  final bool compact;
  final bool veryCompact;
  final String initials;
  final String title;
  final String subtitle;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: 18,
          left: 18,
          right: 36,
          bottom: 12,
          child: Transform.rotate(
            angle: -0.055,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.titleColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(36),
              ),
            ),
          ),
        ),
        Positioned.fill(
          top: 8,
          left: 42,
          right: 10,
          bottom: 26,
          child: Transform.rotate(
            angle: 0.04,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(36),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.panelBackground,
                palette.accent.withValues(alpha: 0.16),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 26,
              compact ? 20 : 24,
              compact ? 20 : 26,
              compact ? 20 : 24,
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (veryCompact) ...[
                        Align(
                          alignment: Alignment.topRight,
                          child: _ProfileSeal(
                            palette: palette,
                            initials: initials,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileIdentityGroup(
                          palette: palette,
                          title: title,
                          subtitle: subtitle,
                          description: description,
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _ProfileIdentityGroup(
                                palette: palette,
                                title: title,
                                subtitle: subtitle,
                                description: description,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _ProfileSeal(
                              palette: palette,
                              initials: initials,
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ProfileIdentityGroup(
                              palette: palette,
                              title: title,
                              subtitle: subtitle,
                              description: description,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: _ProfileSeal(
                                palette: palette,
                                initials: initials,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentityGroup extends StatelessWidget {
  const _ProfileIdentityGroup({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: palette.titleColor,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.bodyColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: palette.bodyColor,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ProfileSeal extends StatelessWidget {
  const _ProfileSeal({required this.palette, required this.initials});

  final ReaderPalette palette;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            palette.accent.withValues(alpha: 0.24),
            palette.panelBackground,
          ],
        ),
        border: Border.all(color: palette.divider),
      ),
      child: Center(
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.pageBackground,
            border: Border.all(color: palette.divider),
          ),
          child: Center(
            child: Text(
              initials,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: palette.titleColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRibbonColumn extends StatelessWidget {
  const _ProfileRibbonColumn({
    required this.palette,
    required this.themeLabel,
    required this.languageLabel,
    required this.statusLabel,
  });

  final ReaderPalette palette;
  final String themeLabel;
  final String languageLabel;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileRibbon(
          palette: palette,
          icon: Icons.palette_rounded,
          label: themeLabel,
        ),
        const SizedBox(height: 10),
        _ProfileRibbon(
          palette: palette,
          icon: Icons.language_rounded,
          label: languageLabel,
        ),
        const SizedBox(height: 10),
        _ProfileRibbon(
          palette: palette,
          icon: Icons.verified_user_rounded,
          label: statusLabel,
        ),
      ],
    );
  }
}

class _ProfileRibbon extends StatelessWidget {
  const _ProfileRibbon({
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
        color: palette.pageBackground.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              Flexible(
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
      ),
    );
  }
}

class _ProfileCurrentRead extends StatelessWidget {
  const _ProfileCurrentRead({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.fallbackTitle,
    required this.fallbackSubtitle,
  });

  final ReaderPalette palette;
  final String title;
  final String subtitle;
  final String fallbackTitle;
  final String fallbackSubtitle;

  @override
  Widget build(BuildContext context) {
    final hasBook = title.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.pageBackground.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.chrome_reader_mode_rounded, color: palette.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasBook ? title : fallbackTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasBook
                        ? (subtitle.isEmpty ? title : subtitle)
                        : fallbackSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.mutedColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileContactCard extends StatelessWidget {
  const _ProfileContactCard({
    required this.width,
    required this.palette,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final ReaderPalette palette;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: palette.accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.titleColor,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    required this.width,
    required this.palette,
    required this.icon,
    required this.value,
    required this.label,
  });

  final double width;
  final ReaderPalette palette;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: palette.accent),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: palette.titleColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.mutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.width,
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final double width;
  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(icon, color: accent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
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
                const SizedBox(width: 8),
                Icon(Icons.arrow_outward_rounded, color: accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileOrb extends StatelessWidget {
  const _ProfileOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
