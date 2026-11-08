/// Which implementation of `CalendarSource` to use.
enum SourceKind {
  /// Android content providers filled by DAVx⁵ (calendar + tasks).
  davxProvider,

  /// Direct CalDAV to the server.
  calDav,
}

/// Platform the app or CLI runs on, as far as source selection cares.
enum SourcePlatform { android, linux, ios, other }

/// Why [SourceSelector] picked a [SourceKind].
enum SourceReason {
  platformHasNoProvider('This platform has no DAVx⁵; using CalDAV.'),
  forcedInSettings('CalDAV is forced in settings.'),
  calendarPermissionDenied('Calendar permission not granted; using CalDAV.'),
  noDavxAccounts('No DAVx⁵ calendars on this device; using CalDAV.'),
  probeFailed('Could not read the device calendars; using CalDAV.'),
  davxAvailable('Reading calendars and tasks synced by DAVx⁵.');

  const SourceReason(this.description);

  /// Short user-facing explanation.
  final String description;
}

/// What the Android bridge reports about the device, without prompting.
final class ProviderProbe {
  const ProviderProbe({
    required this.calendarPermission,
    required this.davxCalendars,
  });

  /// `READ_CALENDAR` is granted.
  final bool calendarPermission;

  /// Number of calendars owned by a DAVx⁵ account (0 when unknown).
  final int davxCalendars;
}

/// Outcome of [SourceSelector.select].
final class SourceDecision {
  const SourceDecision(this.kind, this.reason, {this.error});

  final SourceKind kind;
  final SourceReason reason;

  /// Set when [reason] is [SourceReason.probeFailed].
  final Object? error;

  @override
  String toString() => 'SourceDecision(${kind.name}, ${reason.name})';
}

/// Picks the calendar/task source.
///
/// On Android, the DAVx⁵ provider is used when the calendar permission is
/// granted and at least one DAVx⁵ calendar exists, unless CalDAV is forced in
/// settings. Every other platform uses CalDAV. Task access is not part of the
/// choice: when only the task provider is missing, tasks fall back to CalDAV
/// call by call (see `FallbackSource`).
abstract final class SourceSelector {
  /// [probe] is only called on Android when CalDAV is not forced; it must not
  /// prompt for permissions (it also runs in background jobs).
  static Future<SourceDecision> select({
    required SourcePlatform platform,
    required bool forceCalDav,
    required Future<ProviderProbe> Function() probe,
  }) async {
    if (platform != SourcePlatform.android) {
      return const SourceDecision(
        SourceKind.calDav,
        SourceReason.platformHasNoProvider,
      );
    }
    if (forceCalDav) {
      return const SourceDecision(
        SourceKind.calDav,
        SourceReason.forcedInSettings,
      );
    }
    final ProviderProbe p;
    try {
      p = await probe();
    } on Object catch (e) {
      return SourceDecision(
        SourceKind.calDav,
        SourceReason.probeFailed,
        error: e,
      );
    }
    if (!p.calendarPermission) {
      return const SourceDecision(
        SourceKind.calDav,
        SourceReason.calendarPermissionDenied,
      );
    }
    if (p.davxCalendars <= 0) {
      return const SourceDecision(
        SourceKind.calDav,
        SourceReason.noDavxAccounts,
      );
    }
    return const SourceDecision(
      SourceKind.davxProvider,
      SourceReason.davxAvailable,
    );
  }
}
