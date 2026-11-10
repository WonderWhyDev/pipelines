#!/usr/bin/env bash
# Tests for e2e_suites.sh: suite files in a throwaway dir -> legs.
#
#   bash .github/actions/e2e_suites/e2e_suites.test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/e2e_suites.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# fresh: an empty suites dir for one case
fresh() { rm -rf "$TMP/s" && mkdir -p "$TMP/s"; }
# suite <name> <json>
suite() { printf '%s\n' "$2" >"$TMP/s/$1.json"; }
# out <app>: the script's stdout, or "ERR" when it fails
out() { bash "$SCRIPT" "$TMP/s" "$1" 2>/dev/null || echo ERR; }
# expect "<desc>" <app> "<want stdout>"
expect() {
  local got
  got=$(out "$2")
  if [ "$got" = "$3" ]; then ok "$1"; else bad "$1: want [$3] got [$got]"; fi
}
# expect_err "<desc>" <app> "<part of the error message>"
expect_err() {
  local msg
  if msg=$(bash "$SCRIPT" "$TMP/s" "$2" 2>&1 >/dev/null); then
    bad "$1: did not fail"
  elif printf '%s' "$msg" | grep -qF "$3"; then
    ok "$1"
  else
    bad "$1: error [$msg] lacks [$3]"
  fi
}

NONE='legs=[{"leg":"none"}]
has_legs=false'

echo "no suites"
expect "missing dir" web "$(bash "$SCRIPT" "$TMP/nope" web)"
got=$(bash "$SCRIPT" "$TMP/nope" web)
[ "$got" = "$NONE" ] && ok "missing dir gives the dummy leg" || bad "missing dir: got [$got]"
fresh
expect "empty dir gives the dummy leg" web "$NONE"
suite only_mobile '{"app": "android", "leg": "m1"}'
expect "no suite for this app gives the dummy leg" web "$NONE"

echo "legs"
fresh
suite billing_invoice '{"app": "web", "leg": "billing", "about": "invoices"}'
suite billing_receipts '{"app": "web", "leg": "billing", "mock": true}'
suite books_setup '{"app": "web", "leg": "books"}'
expect "web suites grouped by leg, mock if any suite asks" web 'legs=[{"leg":"billing","mock":true,"timezone":"","suites":"billing_invoice billing_receipts","seeds":"billing_invoice=tool/seed_billing_invoice.dart billing_receipts=tool/seed_billing_receipts.dart","targets":"patrol_test/suites/billing_invoice_test.dart,patrol_test/suites/billing_receipts_test.dart"},{"leg":"books","mock":false,"timezone":"","suites":"books_setup","seeds":"books_setup=tool/seed_books_setup.dart","targets":"patrol_test/suites/books_setup_test.dart"}]
has_legs=true'
expect "android ignores web suites" android "$NONE"

fresh
suite m_trips '{"app": "android", "leg": "mobile_trips"}'
suite m_fuel '{"app": "android", "leg": "mobile_trips", "mock": false}'
expect "android: --target per suite, always mock" android 'legs=[{"leg":"mobile_trips","mock":true,"timezone":"","suites":"m_fuel m_trips","seeds":"m_fuel=tool/seed_m_fuel.dart m_trips=tool/seed_m_trips.dart","targets":"--target patrol_test/suites/m_fuel_test.dart --target patrol_test/suites/m_trips_test.dart"}]
has_legs=true'

fresh
suite ist_a '{"app": "web", "leg": "ist", "timezone": "Asia/Kolkata"}'
suite ist_b '{"app": "web", "leg": "ist", "timezone": "Asia/Kolkata"}'
expect "one timezone per leg" web 'legs=[{"leg":"ist","mock":false,"timezone":"Asia/Kolkata","suites":"ist_a ist_b","seeds":"ist_a=tool/seed_ist_a.dart ist_b=tool/seed_ist_b.dart","targets":"patrol_test/suites/ist_a_test.dart,patrol_test/suites/ist_b_test.dart"}]
has_legs=true'

echo "errors"
fresh
suite tz_a '{"app": "web", "leg": "mixed", "timezone": "Asia/Kolkata"}'
suite tz_b '{"app": "web", "leg": "mixed"}'
expect_err "two timezones in one leg" web "different timezones"
fresh
suite typo '{"app": "web", "leg": "x", "mocks": true}'
expect_err "unknown field" web "unknown field"
fresh
suite noleg '{"app": "web"}'
expect_err "missing leg" web "leg must be"
fresh
suite badleg '{"app": "web", "leg": "Bad-Leg"}'
expect_err "bad leg name" web "leg must be"
fresh
suite badapp '{"app": "ios", "leg": "x"}'
expect_err "bad app" web "app must be"
fresh
suite badmock '{"app": "web", "leg": "x", "mock": "yes"}'
expect_err "mock not boolean" web "mock must be"
fresh
suite mobtz '{"app": "android", "leg": "x", "timezone": "UTC"}'
expect_err "timezone on android" android "web suites only"
fresh
suite 'Bad-Name' '{"app": "web", "leg": "x"}'
expect_err "bad file name" web "file name must be"
fresh
printf 'not json\n' >"$TMP/s/broken.json"
expect_err "broken json" web ""
fresh
suite arr '[1, 2]'
expect_err "not an object" web "JSON object"
expect_err "bad app argument" ios "app must be web or android"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
