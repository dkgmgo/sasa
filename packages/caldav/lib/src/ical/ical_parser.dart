/// Minimal RFC 5545 content-line parser: unfolding, parameters, nested
/// components. Values are kept raw; see `ical_values.dart` for typed reads.
library;

/// One content line, e.g. `DTSTART;TZID=Europe/Paris:20261102T140000`.
final class IcalProperty {
  IcalProperty(this.name, this.params, this.value);

  /// Upper-case property name, e.g. `DTSTART`.
  final String name;

  /// Parameters keyed by upper-case name. Quotes are removed; a parameter
  /// given several values keeps them comma-joined.
  final Map<String, String> params;

  /// Raw value, still escaped for TEXT properties.
  final String value;

  /// Value of parameter [name] (case-insensitive), or null.
  String? param(String name) => params[name.toUpperCase()];

  @override
  String toString() => 'IcalProperty($name, $params, $value)';
}

/// A `BEGIN:X … END:X` block.
final class IcalComponent {
  IcalComponent(this.name);

  /// Upper-case component name, e.g. `VEVENT`.
  final String name;
  final List<IcalProperty> properties = [];
  final List<IcalComponent> children = [];

  /// First property called [name], or null.
  IcalProperty? property(String name) {
    final n = name.toUpperCase();
    for (final p in properties) {
      if (p.name == n) return p;
    }
    return null;
  }

  /// Every property called [name], in file order.
  Iterable<IcalProperty> propertiesNamed(String name) {
    final n = name.toUpperCase();
    return properties.where((p) => p.name == n);
  }

  /// Direct children called [name].
  Iterable<IcalComponent> childrenNamed(String name) {
    final n = name.toUpperCase();
    return children.where((c) => c.name == n);
  }

  @override
  String toString() => 'IcalComponent($name)';
}

/// Parses an iCalendar stream and returns its top-level components
/// (normally one `VCALENDAR`).
///
/// Accepts CRLF or LF line ends. Lines without a colon are skipped.
/// Throws [FormatException] when `BEGIN`/`END` do not nest.
List<IcalComponent> parseIcal(String text) {
  final roots = <IcalComponent>[];
  final stack = <IcalComponent>[];
  for (final line in unfoldLines(text)) {
    final prop = parseContentLine(line);
    if (prop == null) continue;
    if (prop.name == 'BEGIN') {
      final c = IcalComponent(prop.value.trim().toUpperCase());
      if (stack.isEmpty) {
        roots.add(c);
      } else {
        stack.last.children.add(c);
      }
      stack.add(c);
    } else if (prop.name == 'END') {
      final name = prop.value.trim().toUpperCase();
      if (stack.isEmpty || stack.last.name != name) {
        throw FormatException('Unexpected END:$name');
      }
      stack.removeLast();
    } else if (stack.isNotEmpty) {
      stack.last.properties.add(prop);
    }
  }
  if (stack.isNotEmpty) {
    throw FormatException('Missing END:${stack.last.name}');
  }
  return roots;
}

/// Splits [text] into logical lines, joining folded continuation lines
/// (those starting with a space or tab).
List<String> unfoldLines(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  var has = false;
  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isNotEmpty && (line[0] == ' ' || line[0] == '\t')) {
      buf.write(line.substring(1));
      continue;
    }
    if (has) out.add(buf.toString());
    buf.clear();
    buf.write(line);
    has = true;
  }
  if (has) out.add(buf.toString());
  return [
    for (final l in out)
      if (l.isNotEmpty) l,
  ];
}

/// Parses one unfolded content line, or returns null if it has no value.
IcalProperty? parseContentLine(String line) {
  // Find the colon that ends name+params, skipping quoted parameter values.
  var inQuotes = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == ':' && !inQuotes) {
      colon = i;
      break;
    }
  }
  if (colon < 0) return null;
  final head = _splitOutsideQuotes(line.substring(0, colon), ';');
  final name = head.first.trim().toUpperCase();
  if (name.isEmpty) return null;
  final params = <String, String>{};
  for (final part in head.skip(1)) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = part.substring(0, eq).trim().toUpperCase();
    final values = _splitOutsideQuotes(
      part.substring(eq + 1),
      ',',
    ).map(_unquote);
    params[key] = values.join(',');
  }
  return IcalProperty(name, params, line.substring(colon + 1));
}

List<String> _splitOutsideQuotes(String s, String sep) {
  final out = <String>[];
  var inQuotes = false;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == sep && !inQuotes) {
      out.add(s.substring(start, i));
      start = i + 1;
    }
  }
  out.add(s.substring(start));
  return out;
}

String _unquote(String s) {
  final t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

/// Decodes an RFC 5545 TEXT value (`\\`, `\;`, `\,`, `\n`).
String unescapeText(String s) {
  if (!s.contains(r'\')) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length) {
      final next = s[++i];
      b.write(next == 'n' || next == 'N' ? '\n' : next);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// Splits a multi-valued TEXT (e.g. `CATEGORIES:a,b\,c`) on unescaped
/// commas and unescapes each value.
List<String> splitTextList(String s) {
  final out = <String>[];
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == r'\') {
      i++;
    } else if (s[i] == ',') {
      out.add(unescapeText(s.substring(start, i)));
      start = i + 1;
    }
  }
  out.add(unescapeText(s.substring(start)));
  return out;
}
