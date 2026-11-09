import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sasa/src/theme/pwani.dart';
import 'package:sasa_core/sasa_core.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('textOn picks the stronger of Deep and white', () {
    expect(textOn(Pwani.coral), Pwani.deep);
    expect(textOn(Pwani.sand), Pwani.deep);
    expect(textOn(Pwani.sky), Pwani.deep);
    expect(textOn(Pwani.ocean), Pwani.white);
    expect(textOn(Pwani.deep), Pwani.white);
  });

  test('every category palette colour gets readable text', () {
    for (final hex in categoryPalette) {
      final c = Color(parseHexColor(hex)!);
      expect(contrast(textOn(c), c), greaterThanOrEqualTo(3.0), reason: hex);
    }
  });

  test('light theme: Ocean primary, Coral secondary, Deep text on Sky', () {
    final t = pwaniTheme(Brightness.light);
    expect(t.colorScheme.primary, Pwani.oceanInk);
    expect(t.colorScheme.secondary, Pwani.coral);
    expect(t.colorScheme.surface, Pwani.sky);
    expect(t.cardTheme.color, Pwani.white);
    final s = t.colorScheme;
    for (final fg in [s.onSurface, s.onSurfaceVariant, s.primary, s.error]) {
      expect(contrast(fg, s.surface), greaterThanOrEqualTo(4.5), reason: '$fg');
      expect(contrast(fg, Pwani.white), greaterThanOrEqualTo(4.5));
    }
    expect(t.colorScheme.onSurface, Pwani.deep);
    expect(t.textTheme.headlineSmall?.fontFamily, Pwani.headingFont);
    expect(t.textTheme.bodyMedium?.fontFamily, Pwani.bodyFont);
    expect(
      contrast(t.colorScheme.onPrimary, t.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark theme: teal page, lighter cards, readable text', () {
    final t = pwaniTheme(Brightness.dark);
    final s = t.colorScheme;
    expect(s.surface, Pwani.darkBackground);
    expect(t.cardTheme.color, Pwani.darkRaised);
    expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
    // Text sits on the page and on cards.
    for (final bg in [s.surface, Pwani.darkRaised]) {
      for (final fg in [s.onSurface, s.onSurfaceVariant, s.primary, s.error]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg');
      }
      expect(contrast(PwaniColors.dark.now, bg), greaterThanOrEqualTo(4.0));
    }
  });

  test('buttons and chips are pills', () {
    final t = pwaniTheme(Brightness.light);
    expect(t.filledButtonTheme.style?.shape?.resolve({}), isA<StadiumBorder>());
    expect(t.floatingActionButtonTheme.shape, isA<StadiumBorder>());
    expect(t.chipTheme.shape, isA<StadiumBorder>());
  });
}
