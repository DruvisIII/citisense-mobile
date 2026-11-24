import 'package:flutter/material.dart';

// ============================================================
// CITISENSE DESIGN TOKENS
// ------------------------------------------------------------
// Every screen reads its colors from here, so the whole app
// stays consistent. Change a value once and it updates
// everywhere.
// ============================================================

/// Body font used across the whole app (paragraphs, subtitles, hints,
/// inputs). Quicksand: free from Google Fonts (SIL Open Font License).
/// To switch fonts later, change this value and the pubspec.yaml entry.
const String appFontFamily = 'Quicksand';

/// Heading font for titles, names, labels and other bold text.
/// Nunito: free from Google Fonts (SIL Open Font License).
const String appHeadingFontFamily = 'Nunito';

class AppColors {
  AppColors._();

  // ---------------- Brand ----------------
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primarySoft = Color(0xFFEAF1FE);
  static const Color primaryBorder = Color(0xFFC9DAFB);

  // ---------------- Text ----------------
  static const Color ink = Color(0xFF0F2350); // headings & main text
  static const Color textSecondary = Color(0xFF596887); // supporting text
  static const Color textMuted = Color(0xFF8792AA); // hints & placeholders

  // ---------------- Surfaces ----------------
  static const Color background = Color(0xFFF5F8FD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F6FB); // input fills
  static const Color border = Color(0xFFD6DFEC);
  static const Color divider = Color(0xFFECF0F6);
  static const Color disabled = Color(0xFFC5CEDC);

  // ---------------- Status ----------------
  static const Color success = Color(0xFF1E8E4E);
  static const Color successSoft = Color(0xFFE6F6EC);
  static const Color warning = Color(0xFFB86E00);
  static const Color warningSoft = Color(0xFFFFF4DE);
  static const Color danger = Color(0xFFD23F3F);
  static const Color dangerSoft = Color(0xFFFDEBEB);
  static const Color accent = Color(0xFF7C4DDB); // AI / special categories
  static const Color accentSoft = Color(0xFFF1EAFE);

  // ---------------- Effects ----------------
  static const Color shadow = Color(0xFF1E3A6E);
}

// Short aliases kept so existing screens read naturally.
const Color primaryBlue = AppColors.primary;
const Color darkBlue = AppColors.ink;
const Color textGrey = AppColors.textSecondary;
const Color backgroundColor = AppColors.background;

class AppRadius {
  AppRadius._();

  static const double sm = 12; // inputs, buttons, small tiles
  static const double md = 16; // images, inner panels
  static const double lg = 20; // cards
}

// Reusable text styles so the same kind of text looks the same on
// every screen.
class AppText {
  AppText._();

  static const TextStyle pageTitle = TextStyle(
    fontFamily: appHeadingFontFamily,
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: appFontFamily,
    fontSize: 14,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static const TextStyle fieldLabel = TextStyle(
    fontFamily: appHeadingFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontFamily: appHeadingFontFamily,
    fontSize: 12,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w800,
    color: AppColors.textSecondary,
  );

  static const TextStyle link = TextStyle(
    fontFamily: appHeadingFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );
}

class AppShadows {
  AppShadows._();

  static final List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.07),
      blurRadius: 16,
      offset: const Offset(0, 5),
    ),
  ];

  static final List<BoxShadow> soft = [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];
}

// ============================================================
// THEME
// ============================================================

class AppTheme {
  AppTheme._();

  // Headings (display / headline / title) use Nunito; body and label
  // text use Quicksand.
  static TextTheme _textTheme(TextTheme base) {
    final body = base.apply(
      fontFamily: appFontFamily,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    final heading = base.apply(
      fontFamily: appHeadingFontFamily,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    return body.copyWith(
      displayLarge: heading.displayLarge,
      displayMedium: heading.displayMedium,
      displaySmall: heading.displaySmall,
      headlineLarge: heading.headlineLarge,
      headlineMedium: heading.headlineMedium,
      headlineSmall: heading.headlineSmall,
      titleLarge: heading.titleLarge,
      titleMedium: heading.titleMedium,
      titleSmall: heading.titleSmall,
    );
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      error: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      outline: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: appFontFamily,
      scaffoldBackgroundColor: AppColors.background,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.ink),
        titleTextStyle: TextStyle(
          fontFamily: appHeadingFontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),

      iconTheme: const IconThemeData(color: AppColors.textSecondary),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: appHeadingFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: const TextStyle(
            fontFamily: appHeadingFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: appFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 14,
          color: AppColors.textMuted,
        ),
        labelStyle: const TextStyle(
          fontFamily: appFontFamily,
          color: AppColors.textSecondary,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: appFontFamily,
          color: Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.divider,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border,
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: appHeadingFontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 14,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        textColor: AppColors.ink,
      ),
    );
  }
}
