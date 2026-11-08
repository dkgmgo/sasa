import 'package:sasa_core/sasa_core.dart';
import 'package:test/test.dart';

void main() {
  const ready = ProviderProbe(calendarPermission: true, davxCalendars: 2);

  Future<ProviderProbe> Function() probeReturning(ProviderProbe p) =>
      () async => p;

  Never noProbe() => fail('probe must not be called');

  group('SourceSelector.select', () {
    test('Linux and iOS always use CalDAV, without probing', () async {
      for (final platform in [SourcePlatform.linux, SourcePlatform.ios]) {
        final d = await SourceSelector.select(
          platform: platform,
          forceCalDav: false,
          probe: noProbe,
        );
        expect(d.kind, SourceKind.calDav);
        expect(d.reason, SourceReason.platformHasNoProvider);
      }
    });

    test('forced CalDAV wins on Android, without probing', () async {
      final d = await SourceSelector.select(
        platform: SourcePlatform.android,
        forceCalDav: true,
        probe: noProbe,
      );
      expect(d.kind, SourceKind.calDav);
      expect(d.reason, SourceReason.forcedInSettings);
    });

    test(
      'Android with permission and DAVx⁵ calendars uses the provider',
      () async {
        final d = await SourceSelector.select(
          platform: SourcePlatform.android,
          forceCalDav: false,
          probe: probeReturning(ready),
        );
        expect(d.kind, SourceKind.davxProvider);
        expect(d.reason, SourceReason.davxAvailable);
      },
    );

    test('denied calendar permission falls back to CalDAV', () async {
      final d = await SourceSelector.select(
        platform: SourcePlatform.android,
        forceCalDav: false,
        probe: probeReturning(
          const ProviderProbe(calendarPermission: false, davxCalendars: 0),
        ),
      );
      expect(d.kind, SourceKind.calDav);
      expect(d.reason, SourceReason.calendarPermissionDenied);
    });

    test('no DAVx⁵ calendars falls back to CalDAV', () async {
      final d = await SourceSelector.select(
        platform: SourcePlatform.android,
        forceCalDav: false,
        probe: probeReturning(
          const ProviderProbe(calendarPermission: true, davxCalendars: 0),
        ),
      );
      expect(d.kind, SourceKind.calDav);
      expect(d.reason, SourceReason.noDavxAccounts);
    });

    test('a failing probe falls back to CalDAV and keeps the error', () async {
      final d = await SourceSelector.select(
        platform: SourcePlatform.android,
        forceCalDav: false,
        probe: () async => throw StateError('binder died'),
      );
      expect(d.kind, SourceKind.calDav);
      expect(d.reason, SourceReason.probeFailed);
      expect(d.error, isA<StateError>());
    });

    test('decisions describe themselves', () async {
      final d = await SourceSelector.select(
        platform: SourcePlatform.android,
        forceCalDav: false,
        probe: probeReturning(ready),
      );
      expect(d.toString(), contains('davxProvider'));
      expect(d.reason.description, isNotEmpty);
      for (final r in SourceReason.values) {
        expect(r.description, isNotEmpty);
      }
    });
  });
}
