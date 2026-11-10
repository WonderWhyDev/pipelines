#!/usr/bin/env bash
# Pick which legs of one test matrix run: a legs file plus an "only" list.
#
#   bash pick_legs.sh <legs_file> <unit> [only]
#
# legs_file  a JSON list in .github/legs: one object per leg, each with a unique
#            "name" [a-z0-9_]+. Every other field goes to the matrix as it is.
# unit       the word for these legs in "only": journey, functional, e2e.
# only       space-separated units from 1_Branch_Check's plan. Empty: every leg.
#            Otherwise a leg runs when "only" names "<unit>:*" or
#            "<unit>:<name>". Units for other jobs ("lint", "suite:x") are
#            ignored here. A "<unit>:<name>" with no such leg is an error, so a
#            typo or a renamed leg cannot drop a test silently.
#
# Prints two GITHUB_OUTPUT lines:
#   legs=<JSON list for a matrix include>, one dummy {"name":"none"} entry when
#        no leg is picked, so a matrix built from it is never empty
#   has_legs=true|false
set -euo pipefail

file=${1:?usage: pick_legs.sh <legs_file> <unit> [only]}
unit=${2:?usage: pick_legs.sh <legs_file> <unit> [only]}
only=${3:-}

jq -r --arg unit "$unit" --arg only "$only" '
  def check(cond; msg): if cond then . else error(msg) end;
  check(type == "array" and length > 0; "\(input_filename): must be a non-empty JSON list")
  | check(all(.[]; type == "object" and ((.name // null) | type == "string" and test("^[a-z0-9_]+$")));
          "\(input_filename): every leg needs a name [a-z0-9_]+")
  | check((map(.name) | unique | length) == length; "\(input_filename): leg names must be unique")
  | [$only | splits(" +") | select(startswith($unit + ":")) | ltrimstr($unit + ":")] as $want
  | ($want - ["*"] - map(.name)) as $missing
  | check($missing == []; "\(input_filename): no leg named \($missing | join(", ")) for \($unit):")
  | if $only == "" or ($want | index("*")) then .
    else map(select(.name as $n | $want | index($n)))
    end
  | if length == 0 then "legs=[{\"name\":\"none\"}]", "has_legs=false"
    else "legs=\(tojson)", "has_legs=true"
    end
' "$file"
