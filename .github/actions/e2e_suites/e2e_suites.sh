#!/usr/bin/env bash
# Turn wonderWhy's functional-test/suites/*.json into CI legs for one app.
#
#   bash e2e_suites.sh <suites_dir> <web|android> [only]
#
# only: space-separated units from 1_Branch_Check's plan. Empty: every leg.
# Otherwise a leg runs when "only" names "suite:*" or "suite:<leg>"; other
# units ("lint", "journey:x") are for other jobs. A "suite:<leg>" that no suite
# of this app has is an error, so a picked leg cannot vanish silently.
#
# Prints two GITHUB_OUTPUT lines:
#   legs=<JSON list for a matrix include>
#   has_legs=true|false
# With no suite for the app, legs is one dummy {"leg":"none"} entry, so a
# matrix built from it is never empty.
#
# A suite is one file, functional-test/suites/<suite>.json. <suite> is
# [a-z0-9_]+, and it fixes the other paths:
#   seed  functional-test/tool/seed_<suite>.dart, prints "[seed-<suite>] done"
#   test  <app dir>/patrol_test/suites/<suite>_test.dart
# Fields:
#   app       "web" (wondermove_web) or "android" (wondermove_mobile). Required.
#   leg       [a-z0-9_]+. Suites with the same leg run on one stack, seeded one
#             after the other, then one Patrol run. Required.
#   mock      true: the leg gets the compose.mock.yml overlay (OCR/HDFC mock,
#             S3 bucket, mailpit). Any suite asking turns it on for its leg.
#             Default false. Android legs always have it.
#   timezone  web only: the browser's timezone, e.g. "Asia/Kolkata". Default
#             the runner's (UTC). Every suite of a leg must ask for the same one.
#   about     free text, one line on what the suite drives.
# Any other field is an error, so a typo cannot pass silently.
#
# Each leg in the output:
#   leg, mock, timezone ("" = default), suites ("a b"),
#   seeds ("a=tool/seed_a.dart b=tool/seed_b.dart"),
#   targets (web: "patrol_test/suites/a_test.dart,patrol_test/suites/b_test.dart";
#            android: "--target patrol_test/suites/a_test.dart --target ...")
set -euo pipefail

dir=${1:?usage: e2e_suites.sh <suites_dir> <web|android> [only]}
app=${2:?usage: e2e_suites.sh <suites_dir> <web|android> [only]}
only=${3:-}
case "$app" in
  web | android) ;;
  *) echo "e2e_suites: app must be web or android, got '$app'" >&2; exit 2 ;;
esac

files=""
if [ -d "$dir" ]; then
  files=$(find "$dir" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)
fi

if [ -n "$files" ]; then
  while IFS= read -r f; do
    name=$(basename "$f" .json)
    case "$name" in
      "" | *[!a-z0-9_]*)
        echo "e2e_suites: $f: the file name must be [a-z0-9_]+.json" >&2
        exit 1
        ;;
    esac
  done <<<"$files"
fi

if [ -z "$files" ]; then
  case " $only " in
    *" suite:"[!*]*)
      echo "e2e_suites: only names suite legs ($only), but $dir has no suite file" >&2
      exit 1
      ;;
  esac
  echo 'legs=[{"leg":"none"}]'
  echo 'has_legs=false'
  exit 0
fi

# shellcheck disable=SC2086 # names were checked above: no spaces or globs
jq -nr --arg app "$app" --arg only "$only" '
  def check(cond; msg): if cond then . else error(msg) end;
  [inputs | {name: (input_filename | split("/") | last | rtrimstr(".json")), spec: .}]
  | map(
      .name as $n
      | .spec
      | check(type == "object"; "\($n).json: must be a JSON object")
      | check((keys - ["app", "leg", "mock", "timezone", "about"]) == [];
              "\($n).json: unknown field(s) \(keys - ["app", "leg", "mock", "timezone", "about"])")
      | check(.app == "web" or .app == "android"; "\($n).json: app must be \"web\" or \"android\"")
      | check((.leg | type) == "string" and (.leg | test("^[a-z0-9_]+$"));
              "\($n).json: leg must be [a-z0-9_]+")
      | check((has("mock") | not) or ((.mock | type) == "boolean"); "\($n).json: mock must be true or false")
      | check((has("timezone") | not) or ((.timezone | type) == "string" and .timezone != "");
              "\($n).json: timezone must be a non-empty string")
      | check((has("timezone") | not) or .app == "web"; "\($n).json: timezone is for web suites only")
      | check((has("about") | not) or ((.about | type) == "string"); "\($n).json: about must be a string")
      | {name: $n, app, leg, mock: (.mock // false), timezone: (.timezone // "")}
    )
  | map(select(.app == $app))
  | (if length == 0 then []
     else
       group_by(.leg)
       | map(
           . as $s
           | ($s | map(.timezone) | unique) as $tz
           | check(($tz | length) == 1;
                   "leg \($s[0].leg): its suites ask for different timezones \($tz)")
           | {
               leg: $s[0].leg,
               mock: ($app == "android" or ($s | any(.mock))),
               timezone: $tz[0],
               suites: ($s | map(.name) | join(" ")),
               seeds: ($s | map("\(.name)=tool/seed_\(.name).dart") | join(" ")),
               targets: (if $app == "web"
                         then ($s | map("patrol_test/suites/\(.name)_test.dart") | join(","))
                         else ($s | map("--target patrol_test/suites/\(.name)_test.dart") | join(" "))
                         end)
             }
         )
     end) as $all
  | [$only | splits(" +") | select(startswith("suite:")) | ltrimstr("suite:")] as $want
  | ($want - ["*"] - ($all | map(.leg))) as $missing
  | check($missing == []; "only names suite leg(s) \($missing | join(", ")) that no \($app) suite has")
  | (if $only == "" or ($want | index("*")) then $all
     else $all | map(select(.leg as $l | $want | index($l)))
     end) as $legs
  | if ($legs | length) == 0 then "legs=[{\"leg\":\"none\"}]", "has_legs=false"
    else "legs=\($legs | tojson)", "has_legs=true"
    end
' $files
