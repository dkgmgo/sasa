import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The "Pwani" design system: the coast at 7 am. Ocean teal, coral, sand
/// and sky, Lexend headings over Inter body text, arch tops, pill buttons
/// and wave lines.
///
/// Screens read colours and shapes from the theme; only this folder holds
/// literal values.
abstract final class Pwani {
  static const ocean = Color(0xFF0B7474);
  static const coral = Color(0xFFFF7A5C);
  static const sand = Color(0xFFF3E3C3);
  static const sky = Color(0xFFBDE7EC);
  static const deep = Color(0xFF0E3B43);
  static const mist = Color(0xFFF4FAFA);
  static const white = Color(0xFFFFFFFF);

  /// Ocean a shade deeper: the light primary, so Ocean text on the Sky
  /// background reaches 4.5:1 (Ocean itself gives 4.2:1).
  static const oceanInk = Color(0xFF0A6A6A);

  /// Ocean lightened, for waves and accents on dark backgrounds.
  static const lagoon = Color(0xFF5CC2BC);

  /// Lighter Lagoon: the dark primary, 4.5:1 on dark cards.
  static const lagoonLight = Color(0xFFA3E5E0);
  static const coralTint = Color(0xFFFFE2DA);
  static const coralInk = Color(0xFF8A2A12);

  /// Light Coral for the "now" marker on dark backgrounds.
  static const coralLight = Color(0xFFFFBCA9);

  /// Dark mode: a mid teal page, lighter cards on it.
  static const darkBackground = Color(0xFF15535B);
  static const darkRaised = Color(0xFF1D6670);
  static const darkSunken = Color(0xFF0F444B);

  static const headingFont = 'Lexend';
  static const bodyFont = 'Inter';

  static const cardRadius = 24.0;
}

/// Deep or white, whichever contrasts more with [background] (WCAG
/// relative luminance).
Color textOn(Color background) {
  final bg = background.computeLuminance();
  double ratio(Color c) {
    final l = c.computeLuminance();
    return (math.max(l, bg) + 0.05) / (math.min(l, bg) + 0.05);
  }

  return ratio(Pwani.deep) >= ratio(Pwani.white) ? Pwani.deep : Pwani.white;
}

/// Extra colours of the design system that [ColorScheme] has no slot for.
@immutable
class PwaniColors extends ThemeExtension<PwaniColors> {
  const PwaniColors({
    required this.wave,
    required this.waveShallow,
    required this.waveDeep,
    required this.now,
    required this.cardShadow,
  });

  static const light = PwaniColors(
    wave: Pwani.sky,
    waveShallow: Pwani.lagoon,
    waveDeep: Pwani.ocean,
    now: Pwani.coral,
    cardShadow: Color(0x140E3B43),
  );

  static const dark = PwaniColors(
    wave: Color(0x665CC2BC),
    waveShallow: Pwani.darkRaised,
    waveDeep: Pwani.deep,
    now: Pwani.coralLight,
    cardShadow: Color(0x66000000),
  );

  /// Wave lines and the light layer of the footer wave.
  final Color wave;

  /// The upper layer of the footer wave (not the page colour).
  final Color waveShallow;

  /// The deep layer of the footer wave.
  final Color waveDeep;

  /// The "now" marker.
  final Color now;
  final Color cardShadow;

  static PwaniColors of(BuildContext context) =>
      Theme.of(context).extension<PwaniColors>() ?? light;

  @override
  PwaniColors copyWith({
    Color? wave,
    Color? waveShallow,
    Color? waveDeep,
    Color? now,
    Color? cardShadow,
  }) => PwaniColors(
    wave: wave ?? this.wave,
    waveShallow: waveShallow ?? this.waveShallow,
    waveDeep: waveDeep ?? this.waveDeep,
    now: now ?? this.now,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  PwaniColors lerp(PwaniColors? other, double t) {
    if (other == null) return this;
    return PwaniColors(
      wave: Color.lerp(wave, other.wave, t)!,
      waveShallow: Color.lerp(waveShallow, other.waveShallow, t)!,
      waveDeep: Color.lerp(waveDeep, other.waveDeep, t)!,
      now: Color.lerp(now, other.now, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
    );
  }
}

ColorScheme _scheme(Brightness b) {
  final light = b == Brightness.light;
  return ColorScheme.fromSeed(seedColor: Pwani.ocean, brightness: b).copyWith(
    primary: light ? Pwani.oceanInk : Pwani.lagoonLight,
    onPrimary: light ? Pwani.white : Pwani.deep,
    primaryContainer: light ? Pwani.sky : Pwani.darkSunken,
    onPrimaryContainer: light ? Pwani.deep : Pwani.sky,
    secondary: Pwani.coral,
    onSecondary: Pwani.deep,
    secondaryContainer: light ? Pwani.coralTint : Pwani.coral,
    onSecondaryContainer: light ? Pwani.coralInk : Pwani.deep,
    tertiary: light ? Pwani.ocean : Pwani.sky,
    onTertiary: light ? Pwani.white : Pwani.deep,
    tertiaryContainer: Pwani.sand,
    onTertiaryContainer: Pwani.deep,
    error: light ? const Color(0xFFB3261E) : const Color(0xFFFFCCC5),
    onError: light ? Pwani.white : const Color(0xFF690005),
    errorContainer: light ? const Color(0xFFF9DEDC) : const Color(0xFF8C1D18),
    onErrorContainer: light ? const Color(0xFF410E0B) : const Color(0xFFFFDAD6),
    surface: light ? Pwani.sky : Pwani.darkBackground,
    onSurface: light ? Pwani.deep : const Color(0xFFE3F1F2),
    onSurfaceVariant: light ? const Color(0xFF3F6168) : const Color(0xFFC3DBDE),
    surfaceContainerLowest: light ? Pwani.white : Pwani.darkSunken,
    surfaceContainerLow: light ? Pwani.white : Pwani.darkRaised,
    surfaceContainer: light ? Pwani.white : Pwani.darkRaised,
    surfaceContainerHigh: light
        ? const Color(0xFFEAF4F5)
        : const Color(0xFF247580),
    surfaceContainerHighest: light
        ? const Color(0xFFDDEDEF)
        : const Color(0xFF2B828C),
    outline: light ? const Color(0xFF5F8A90) : const Color(0xFF8FB5BA),
    outlineVariant: light ? const Color(0xFFA6CFD5) : const Color(0xFF2E7A84),
    inverseSurface: light ? Pwani.deep : Pwani.mist,
    onInverseSurface: light ? Pwani.mist : Pwani.deep,
    inversePrimary: light ? Pwani.lagoon : Pwani.ocean,
    shadow: Pwani.deep,
  );
}

TextTheme _text(ColorScheme s) {
  final base = Typography.material2021(platform: defaultTargetPlatform)
      .englishLike
      .apply(fontFamily: Pwani.bodyFont);
  TextStyle? heading(TextStyle? t, FontWeight w) =>
      t?.copyWith(fontFamily: Pwani.headingFont, fontWeight: w);
  return base
      .copyWith(
        displayLarge: heading(base.displayLarge, FontWeight.w600),
        displayMedium: heading(base.displayMedium, FontWeight.w600),
        displaySmall: heading(base.displaySmall, FontWeight.w600),
        headlineLarge: heading(base.headlineLarge, FontWeight.w600),
        headlineMedium: heading(base.headlineMedium, FontWeight.w600),
        headlineSmall: heading(base.headlineSmall, FontWeight.w600),
        titleLarge: heading(base.titleLarge, FontWeight.w600),
        titleMedium: heading(base.titleMedium, FontWeight.w500),
        titleSmall: heading(base.titleSmall, FontWeight.w600),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      )
      .apply(bodyColor: s.onSurface, displayColor: s.onSurface);
}

const _pill = StadiumBorder();
const _buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 12);

/// The Pwani [ThemeData] for [brightness].
ThemeData pwaniTheme(Brightness brightness) {
  final s = _scheme(brightness);
  final light = brightness == Brightness.light;
  final text = _text(s);
  final cardColor = light ? Pwani.white : Pwani.darkRaised;
  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    fontFamily: Pwani.bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    extensions: [light ? PwaniColors.light : PwaniColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
      systemOverlayStyle: light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      // Soft Deep-tinted shadow; no border.
      elevation: light ? 3 : 0,
      shadowColor: const Color(0x590E3B43),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Pwani.cardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: _pill, padding: _buttonPadding),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _pill,
        padding: _buttonPadding,
        side: BorderSide(color: s.primary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: _pill),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: _pill, padding: _buttonPadding),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: s.primaryContainer,
        selectedForegroundColor: s.onPrimaryContainer,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      shape: _pill,
      extendedTextStyle: text.labelLarge?.copyWith(
        fontFamily: Pwani.headingFont,
        fontSize: 16,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: _pill,
      side: BorderSide.none,
      backgroundColor: light ? Pwani.sand : Pwani.darkRaised,
      labelStyle: text.labelLarge?.copyWith(
        color: light ? Pwani.deep : s.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      indicatorColor: light ? Pwani.sky : Pwani.lagoon.withValues(alpha: 0.24),
      indicatorShape: _pill,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? s.onPrimaryContainer
              : s.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStatePropertyAll(
        text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cardColor,
      indicatorColor: light ? Pwani.sky : Pwani.lagoon.withValues(alpha: 0.24),
      indicatorShape: _pill,
      selectedIconTheme: IconThemeData(color: s.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: s.onSurfaceVariant),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: Pwani.coral,
      textColor: Pwani.deep,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Pwani.cardRadius),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Pwani.cardRadius),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: _pill,
      backgroundColor: light ? Pwani.deep : Pwani.sky,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: light ? Pwani.white : Pwani.deep,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.primary, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(s.outlineVariant),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.primary,
      linearTrackColor: light ? Pwani.sky : Pwani.darkRaised,
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );
}

/// Registers the bundled fonts' licences so they show in the licence page.
void registerFontLicences() => LicenseRegistry.addLicense(() async* {
  for (final (family, file) in const [
    ('Lexend', 'assets/fonts/Lexend-OFL.txt'),
    ('Inter', 'assets/fonts/Inter-OFL.txt'),
  ]) {
    yield LicenseEntryWithLineBreaks([
      family,
    ], await rootBundle.loadString(file));
  }
});
