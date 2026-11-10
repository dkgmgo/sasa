import 'package:sasa_core/sasa_core.dart';

/// systemd user units for Sasa's background jobs on Linux.

const briefService = 'sasa-brief.service';
const briefTimer = 'sasa-brief.timer';
const tickService = 'sasa-tick.service';
const tickTimer = 'sasa-tick.timer';

/// How often `sasa tick` runs.
const tickOnCalendar = '*:0/15';

const _header =
    '# Written by `sasa install-timers`. `sasa tick` rewrites $briefTimer\n'
    '# when the brief settings in config.json change.\n';

/// `$XDG_CONFIG_HOME/systemd/user`, else `~/.config/systemd/user`; null
/// when neither variable is set.
String? systemdUserUnitDir(Map<String, String> env) {
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/systemd/user';
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  return '$home/.config/systemd/user';
}

/// The `OnCalendar=` value for the brief, in the configured [timeZone] so
/// the brief follows config.json even when the machine's zone differs:
/// `Mon..Fri *-*-* 07:30:00 Europe/Paris`.
String briefOnCalendar(BriefSettings brief, String timeZone) {
  final days = switch (brief.days) {
    BriefDays.weekdays => 'Mon..Fri ',
    BriefDays.everyDay => '',
  };
  return '$days*-*-* ${brief.time}:00 $timeZone';
}

/// Quotes one `ExecStart=` word for systemd: `%` and `$` are escaped, and
/// words with spaces, quotes or backslashes are double-quoted.
String systemdQuote(String word) {
  var w = word.replaceAll('%', '%%').replaceAll(r'$', r'$$');
  if (w.isEmpty ||
      RegExp(
        r'[\s"\\'
        "']",
      ).hasMatch(w)) {
    w = '"${w.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  return w;
}

String _exec(List<String> words) => words.map(systemdQuote).join(' ');

/// The brief timer, which `sasa tick` keeps in line with config.json.
String briefTimerUnit(BriefSettings brief, String timeZone) =>
    '''
$_header
[Unit]
Description=Sasa morning brief at ${brief.time}${brief.days == BriefDays.weekdays ? ' on weekdays' : ''}

[Timer]
OnCalendar=${briefOnCalendar(brief, timeZone)}
# Catch up after sleep or shutdown; `sasa brief --scheduled` skips a brief
# more than ${briefLateLimit.inHours} h late.
Persistent=true

[Install]
WantedBy=timers.target
''';

/// All four units, by file name. [command] is the `sasa` executable and its
/// global options (e.g. `--folder`); [unitDir] is where they are written,
/// which `sasa tick` needs to find the brief timer.
Map<String, String> systemdUnits({
  required List<String> command,
  required String unitDir,
  required BriefSettings brief,
  required String timeZone,
}) => {
  briefService:
      '''
$_header
[Unit]
Description=Sasa morning brief

[Service]
Type=oneshot
ExecStart=${_exec([...command, 'brief', '--scheduled'])}
''',
  briefTimer: briefTimerUnit(brief, timeZone),
  tickService:
      '''
$_header
[Unit]
Description=Sasa background tick (due nudges and reports)

[Service]
Type=oneshot
ExecStart=${_exec([...command, 'tick', '--unit-dir', unitDir])}
''',
  tickTimer:
      '''
$_header
[Unit]
Description=Sasa background tick every 15 minutes

[Timer]
OnCalendar=$tickOnCalendar

[Install]
WantedBy=timers.target
''',
};
