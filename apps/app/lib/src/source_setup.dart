import 'package:davx_bridge/davx_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:sasa_core/sasa_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'device_settings.dart';

/// Reason given while no CalDAV account is set up on this device.
const calDavNotConfigured = 'CalDAV account not configured';

/// [SourcePlatform] of the running app.
SourcePlatform currentSourcePlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.android => SourcePlatform.android,
  TargetPlatform.linux => SourcePlatform.linux,
  TargetPlatform.iOS => SourcePlatform.ios,
  _ => SourcePlatform.other,
};

/// The chosen source and why.
final class SourceSetup {
  const SourceSetup({
    required this.decision,
    required this.source,
    this.status,
  });

  final SourceDecision decision;
  final CalendarSource source;

  /// Provider state on Android (null elsewhere or when not probed).
  final BridgeStatus? status;
}

/// Picks and builds the [CalendarSource]. Never prompts for permissions, so
/// it also works in background jobs.
///
/// With the DAVx⁵ provider, any call that hits a missing permission or task
/// provider falls back to [calDav] (e.g. tasks when Tasks.org is missing).
/// [calDav] is null until a CalDAV account is configured; calls that need it
/// then fail with [SourceUnavailable].
Future<SourceSetup> setUpSource({
  required SourcePlatform platform,
  required DeviceSettings settings,
  required DavxBridgeApi bridge,
  required tz.Location zone,
  CalendarSource? calDav,
  FallbackHandler? onFallback,
}) async {
  final fallback = calDav ?? const UnavailableSource(calDavNotConfigured);
  final provider = DavxProviderSource(bridge: bridge, zone: zone);
  BridgeStatus? status;
  final decision = await SourceSelector.select(
    platform: platform,
    forceCalDav: await settings.forceCalDav(),
    probe: provider.probe,
  );
  if (platform == SourcePlatform.android) {
    try {
      status = await bridge.status();
    } on Object {
      status = null;
    }
  }
  final source = switch (decision.kind) {
    SourceKind.davxProvider => FallbackSource(
      primary: provider,
      fallback: fallback,
      onFallback: onFallback,
    ),
    SourceKind.calDav => fallback,
  };
  return SourceSetup(decision: decision, source: source, status: status);
}
