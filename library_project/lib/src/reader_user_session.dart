class ReaderUserSession {
  const ReaderUserSession({
    required this.displayName,
    required this.email,
    this.phoneNumber = '',
    this.categoryPickerPending = false,
    this.welcomeBannerPending = false,
    required this.isGuest,
  });

  final String displayName;
  final String email;
  final String phoneNumber;
  final bool categoryPickerPending;
  final bool welcomeBannerPending;
  final bool isGuest;

  String get preferredLabel {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    if (email.trim().isNotEmpty) {
      return email.trim();
    }
    if (phoneNumber.trim().isNotEmpty) {
      return phoneNumber.trim();
    }
    return '';
  }

  ReaderUserSession copyWith({
    String? displayName,
    String? email,
    String? phoneNumber,
    bool? categoryPickerPending,
    bool? welcomeBannerPending,
    bool? isGuest,
  }) {
    return ReaderUserSession(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      categoryPickerPending:
          categoryPickerPending ?? this.categoryPickerPending,
      welcomeBannerPending: welcomeBannerPending ?? this.welcomeBannerPending,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
