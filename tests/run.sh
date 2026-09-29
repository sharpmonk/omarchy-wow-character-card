#!/bin/bash

# Runs every automated check that exists so far.
#   tests/run.sh

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
status=0

run() {
  echo "== $*"
  "$@" || status=1
}

run lua5.1 tests/addon/run.lua
[[ -f tests/addon/events.lua ]] && run lua5.1 tests/addon/events.lua
[[ -x tests/helper/run.sh ]] && run tests/helper/run.sh
[[ -f manifest.json ]] && run omarchy plugin validate .

exit $status
