#!/usr/bin/env bash
# (Re)create the test collections and upload the fixtures in seed/.
# Safe to run repeatedly: existing collections are deleted first.
set -euo pipefail
cd "$(dirname "$0")"

base="${SASA_RADICALE_URL:-http://127.0.0.1:${SASA_RADICALE_PORT:-5232}}"
auth="test:test"
user_url="${base}/test"

dav() { # method url [curl args...]
  local method=$1 url=$2; shift 2
  curl -sS -o /dev/null -w '%{http_code}' -u "$auth" -X "$method" "$url" "$@"
}

expect() { # code-pattern actual what
  if [[ ! $2 =~ ^($1)$ ]]; then
    echo "FAILED: $3 (HTTP $2)" >&2
    exit 1
  fi
}

mkcalendar() { # slug displayname component
  local url="${user_url}/$1/"
  dav DELETE "$url" >/dev/null || true
  local code
  code=$(dav MKCALENDAR "$url" -H 'Content-Type: application/xml; charset=utf-8' --data-binary @- <<XML
<?xml version="1.0" encoding="utf-8"?>
<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:set><D:prop>
    <D:displayname>$2</D:displayname>
    <C:supported-calendar-component-set><C:comp name="$3"/></C:supported-calendar-component-set>
  </D:prop></D:set>
</C:mkcalendar>
XML
)
  expect '201' "$code" "MKCALENDAR $url"
  echo "created $url ($3)"
}

upload() { # slug dir
  local f code
  for f in "$2"/*.ics; do
    # iCalendar requires CRLF line endings; fixtures are stored with LF.
    code=$(sed 's/$/\r/' "$f" | dav PUT "${user_url}/$1/$(basename "$f")" \
      -H 'Content-Type: text/calendar; charset=utf-8' --data-binary @-)
    expect '201|204' "$code" "PUT $f"
    echo "  + $(basename "$f")"
  done
}

# Touching the principal makes Radicale create the user's home collection.
expect '207' "$(dav PROPFIND "${user_url}/" -H 'Depth: 0')" "PROPFIND principal"

mkcalendar sasa-calendar 'Sasa test calendar' VEVENT
upload sasa-calendar seed/events
mkcalendar sasa-tasks 'Sasa test tasks' VTODO
upload sasa-tasks seed/tasks

echo "Seeded ${user_url}/ (user test / password test)."
