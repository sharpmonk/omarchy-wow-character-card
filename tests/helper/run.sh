#!/bin/bash

# Tests for bin/wcc. Plain bash and jq, nothing to install.
#   tests/helper/run.sh            run everything
#   tests/helper/run.sh sessions   run tests whose name contains "sessions"
#
# Each test gets a fresh sandbox: a fake /proc, a fake games folder and an
# empty state folder.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WCC="$ROOT/bin/wcc"
FILTER="${1:-}"
PASSED=0
FAILED=0
CURRENT=""

export TZ=UTC
export WCC_CLK_TCK=100
export WCC_ADDON_SRC="$ROOT/addon/WoWCharacterCard"

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL $CURRENT: $1"
}

eq() {
  local name="$1" got="$2" want="$3"
  if [[ $got == "$want" ]]; then
    PASSED=$((PASSED + 1))
  else
    fail "$name"$'\n'"  want: $want"$'\n'"  got:  $got"
  fi
}

sandbox() {
  SANDBOX=$(mktemp -d)
  export WCC_STATE_DIR="$SANDBOX/state"
  export WCC_PROC_DIR="$SANDBOX/proc"
  export WCC_SEARCH_ROOTS="$SANDBOX/search"
  export WCC_NOW=1000000
  unset WCC_EXTRA_DIRS WCC_WOW_DIR WCC_DEMO
  mkdir -p "$WCC_PROC_DIR" "$SANDBOX/search"
  echo "btime 900000" >"$WCC_PROC_DIR/stat"
  # The real folder name has spaces and brackets in it, so the fixtures do too.
  GAMES="$SANDBOX/prefix/drive_c/Program Files (x86)/World of Warcraft"
}

make_install() {
  mkdir -p "$GAMES/$1/WTF" "$GAMES/$1/Interface/AddOns"
  echo "$GAMES/$1"
}

# make_proc <pid> <comm> <cmdline> <cwd> <start-ticks>
make_proc() {
  local dir="$WCC_PROC_DIR/$1"
  mkdir -p "$dir"
  echo "$2" >"$dir/comm"
  printf '%s\0\0\0' "$3" >"$dir/cmdline"
  ln -sfn "$4" "$dir/cwd"
  echo "$1 ($2) S 1 1 1 0 -1 4194304 0 0 0 0 0 0 0 0 20 0 1 0 $5 0 0" >"$dir/stat"
}

# make_data <install> <account> <json>
make_data() {
  local dir="$1/WTF/Account/$2/SavedVariables"
  mkdir -p "$dir"
  {
    echo
    echo "WoWCharacterCardDB = {"
    echo "[\"schema\"] = 1,"
    echo "[\"data\"] = \"$(printf '%s' "$3" | base64 -w 0)\","
    echo "[\"characters\"] = {"
    echo "},"
    echo "}"
  } >"$dir/WoWCharacterCard.lua"
}

character() {
  # character <name> <level> <updatedAt> [extra jq object]
  jq -n -c --arg n "$1" --argjson l "$2" --argjson u "$3" --argjson extra "${4:-{\}}" \
    '{schema: 1, addonVersion: "1.0.0", characters: {("\($n)-Realm"): ({name: $n, realm: "Realm", level: $l, updatedAt: $u} + $extra)}}'
}

run_test() {
  CURRENT="$1"
  [[ -z $FILTER || $1 == *"$FILTER"* ]] || return 0
  sandbox
  "$1"
  rm -rf "$SANDBOX"
}

# ------------------------------------------------------------------ running

test_running_nothing() {
  eq "no game" "$("$WCC" running)" "null"
}

test_running_forever() {
  local install
  install=$(make_install _classic_beta_)
  make_proc 466486 WowB.exe 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\WowB.exe -launcherlogin -uid wow_classic_beta' "$install" 5000
  local out
  out=$("$WCC" running)
  eq "flavor" "$(jq -r .flavor <<<"$out")" "_classic_beta_"
  eq "label" "$(jq -r .label <<<"$out")" "Forever"
  eq "uid" "$(jq -r .uid <<<"$out")" "wow_classic_beta"
  eq "install keeps spaces and brackets" "$(jq -r .install <<<"$out")" "$install"
  eq "pid" "$(jq -r .pid <<<"$out")" "466486"
  eq "started from boot time and ticks" "$(jq -r .started <<<"$out")" "900050"
}

test_running_retail_mixed_case() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'C:\x\_retail_\WoW.exe -launcherlogin -uid wow' "$install" 100
  eq "retail found" "$("$WCC" running | jq -r .flavor)" "_retail_"
  eq "retail uid" "$("$WCC" running | jq -r .uid)" "wow"
}

test_running_without_uid() {
  local install
  install=$(make_install _classic_era_)
  make_proc 10 WowClassic.exe 'C:\x\_classic_era_\WowClassic.exe' "$install" 100
  eq "flavor from folder" "$("$WCC" running | jq -r .flavor)" "_classic_era_"
  eq "uid empty" "$("$WCC" running | jq -r .uid)" ""
}

test_running_ignores_other_programs() {
  local install
  install=$(make_install _retail_)
  make_proc 10 Battle.net.exe 'C:\Battle.net\Battle.net.exe' "$install" 100
  make_proc 11 WowVoiceProxy.e 'C:\x\_retail_\Utils\WowVoiceProxy.exe' "$install" 100
  make_proc 12 wowup-cf-beta '/opt/wowup-cf-beta/wowup-cf-beta' "$install" 100
  make_proc 13 BlizzardError.e 'C:\x\BlizzardError.exe' "$install" 100
  eq "nothing counted" "$("$WCC" running)" "null"
}

test_running_ignores_game_outside_install() {
  mkdir -p "$SANDBOX/elsewhere"
  make_proc 10 Wow.exe 'C:\x\Wow.exe' "$SANDBOX/elsewhere" 100
  eq "not an install" "$("$WCC" running)" "null"
}

test_running_picks_most_recent() {
  local retail forever
  retail=$(make_install _retail_)
  forever=$(make_install _classic_beta_)
  make_proc 10 WoW.exe 'x -uid wow' "$retail" 900
  make_proc 11 WowB.exe 'x -uid wow_classic_beta' "$forever" 500
  eq "latest start wins" "$("$WCC" running | jq -r .flavor)" "_retail_"
}

test_running_start_never_in_future() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 99999999
  eq "clamped to now" "$("$WCC" running | jq -r .started)" "1000000"
}

# ----------------------------------------------------------------- installs

test_installs_manual_root_folder() {
  make_install _retail_ >/dev/null
  make_install _classic_beta_ >/dev/null
  export WCC_EXTRA_DIRS="$GAMES"
  eq "both versions" "$("$WCC" installs | jq -r '[.[].flavor] | sort | join(",")')" "_classic_beta_,_retail_"
  eq "source manual" "$("$WCC" installs | jq -r '.[0].source')" "manual"
}

test_installs_manual_version_folder() {
  local install
  install=$(make_install _retail_)
  make_install _classic_beta_ >/dev/null
  export WCC_EXTRA_DIRS="$SANDBOX/missing:$install/"
  eq "only the one named" "$("$WCC" installs | jq -r '[.[].flavor] | join(",")')" "_retail_"
}

test_installs_manual_folder_with_tilde() {
  export HOME="$SANDBOX/home"
  GAMES="$HOME/Games/World of Warcraft"
  make_install _retail_ >/dev/null
  export WCC_EXTRA_DIRS="~/Games/World of Warcraft"
  eq "tilde means home" "$("$WCC" installs | jq -r '.[0].path')" "$GAMES/_retail_"
}

test_installs_rescan_searches_roots() {
  GAMES="$SANDBOX/search/lutris/wow/drive_c/Program Files (x86)/World of Warcraft"
  make_install _classic_ >/dev/null
  eq "not found before rescan" "$("$WCC" installs | jq length)" "0"
  eq "found by rescan" "$("$WCC" installs --rescan | jq -r '.[0].label')" "Classic"
  eq "source search" "$("$WCC" installs | jq -r '.[0].source')" "search"
}

test_installs_never_launched_game() {
  mkdir -p "$GAMES/_retail_/Interface"
  export WCC_EXTRA_DIRS="$GAMES"
  eq "interface folder alone is enough" "$("$WCC" installs | jq -r '.[0].flavor')" "_retail_"
}

test_installs_damaged_state_file() {
  mkdir -p "$WCC_STATE_DIR"
  echo '{"not": "a list' >"$WCC_STATE_DIR/installs.json"
  eq "treated as empty" "$("$WCC" installs | jq length)" "0"
}

test_installs_addon_state() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  eq "missing" "$("$WCC" installs | jq -r '.[0].addon')" "missing"
  "$WCC" install-addon >/dev/null
  eq "ok" "$("$WCC" installs | jq -r '.[0].addon')" "ok"
  sed -i 's/^## Version:.*/## Version: 0.9.0/' "$install/Interface/AddOns/WoWCharacterCard/WoWCharacterCard.toc"
  eq "outdated" "$("$WCC" installs | jq -r '.[0].addon')" "outdated"
  sed -i 's/^## Version:.*/## Version: 99.0.0/' "$install/Interface/AddOns/WoWCharacterCard/WoWCharacterCard.toc"
  eq "newer than bundled is fine" "$("$WCC" installs | jq -r '.[0].addon')" "ok"
}

test_installs_unknown_version_label() {
  mkdir -p "$GAMES/_some_new_game_/Interface"
  export WCC_EXTRA_DIRS="$GAMES"
  eq "tidied folder name" "$("$WCC" installs | jq -r '.[0].label')" "some new game"
}

# --------------------------------------------------------------- characters

test_characters_none() {
  export WCC_EXTRA_DIRS="$(make_install _retail_)"
  eq "empty list" "$("$WCC" characters)" "[]"
}

test_characters_sorted_across_installs_and_accounts() {
  local retail forever
  retail=$(make_install _retail_)
  forever=$(make_install _classic_beta_)
  export WCC_EXTRA_DIRS="$GAMES"
  make_data "$retail" "111#1" "$(character Oldmain 80 100)"
  make_data "$forever" "111#1" "$(character Exampla 42 300)"
  make_data "$forever" "222#2" "$(character Bankalt 5 200)"
  eq "most recent first" "$("$WCC" characters | jq -r '[.[].name] | join(",")')" "Exampla,Bankalt,Oldmain"
  eq "version label attached" "$("$WCC" characters | jq -r '.[0].label')" "Forever"
}

test_characters_same_name_in_two_versions() {
  local retail forever
  retail=$(make_install _retail_)
  forever=$(make_install _classic_beta_)
  export WCC_EXTRA_DIRS="$GAMES"
  make_data "$retail" "111#1" "$(character Exampla 80 100)"
  make_data "$forever" "111#1" "$(character Exampla 42 300)"
  eq "both kept" "$("$WCC" characters | jq length)" "2"
  eq "ids differ" "$("$WCC" characters | jq -r '[.[].id] | unique | length')" "2"
}

test_characters_accents_and_apostrophes() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" '{"schema":1,"addonVersion":"1.0.0","characters":{"Thrâll-Pozzo dell'"'"'Eternità":{"name":"Thrâll","realm":"Pozzo dell'"'"'Eternità","level":10,"updatedAt":5}}}'
  eq "name" "$("$WCC" characters | jq -r '.[0].name')" "Thrâll"
  eq "realm" "$("$WCC" characters | jq -r '.[0].realm')" "Pozzo dell'Eternità"
}

test_characters_derived_values() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Exampla 42 300 '{"xp":610,"xpMax":1000,"rested":180,"money":3124005,"session":{"startedAt":1,"startLevel":40,"xpGained":900,"moneyDelta":-10250}}')"
  local out
  out=$("$WCC" characters | jq -c '.[0]')
  eq "xp percent" "$(jq -r .xpPercent <<<"$out")" "61"
  eq "rested percent" "$(jq -r .restedPercent <<<"$out")" "18"
  eq "money" "$(jq -r .moneyText <<<"$out")" "312g 40s 5c"
  eq "levels gained" "$(jq -r .session.levelsGained <<<"$out")" "2"
  eq "money lost" "$(jq -r .session.moneyText <<<"$out")" "-1g 2s 50c"
}

test_characters_money_edges() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Rich 80 3 '{"money":99999999999}')"
  make_data "$install" "222#1" "$(character Poor 1 2 '{"money":7}')"
  make_data "$install" "333#1" "$(character Silver 1 1 '{"money":250}')"
  eq "gold cap" "$("$WCC" characters | jq -r '.[0].moneyText')" "9999999g 99s 99c"
  eq "copper only" "$("$WCC" characters | jq -r '.[1].moneyText')" "7c"
  eq "silver and copper" "$("$WCC" characters | jq -r '.[2].moneyText')" "2s 50c"
}

test_characters_max_level() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Oldmain 80 100 '{"atMaxLevel":true}')"
  eq "no xp percent" "$("$WCC" characters | jq -r '.[0].xpPercent')" "null"
  eq "no session" "$("$WCC" characters | jq -r '.[0].session')" "null"
}

test_characters_damaged_file_uses_last_good() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  eq "first read" "$("$WCC" characters | jq -r '.[0].level')" "42"
  echo 'WoWCharacterCardDB = { ["data"] = "e30' >"$install/WTF/Account/111#1/SavedVariables/WoWCharacterCard.lua"
  eq "half-written file" "$("$WCC" characters | jq -r '.[0].level')" "42"
  : >"$install/WTF/Account/111#1/SavedVariables/WoWCharacterCard.lua"
  eq "empty file" "$("$WCC" characters | jq -r '.[0].level')" "42"
}

test_characters_damaged_file_without_history() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  mkdir -p "$install/WTF/Account/111#1/SavedVariables"
  echo '["data"] = "bm90IGpzb24=",' >"$install/WTF/Account/111#1/SavedVariables/WoWCharacterCard.lua"
  eq "skipped" "$("$WCC" characters)" "[]"
}

test_characters_skips_incomplete_records() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" '{"schema":1,"characters":{"A-R":{"name":"A","level":5,"updatedAt":1},"B-R":{"realm":"R"},"C-R":"junk"}}'
  eq "only the complete one" "$("$WCC" characters | jq -r '[.[].name] | join(",")')" "A"
}

test_characters_ignores_backup_files() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  cp "$install/WTF/Account/111#1/SavedVariables/WoWCharacterCard.lua" \
    "$install/WTF/Account/111#1/SavedVariables/WoWCharacterCard.lua.bak"
  eq "counted once" "$("$WCC" characters | jq length)" "1"
}

test_characters_beta_folder_with_other_game() {
  local install
  install=$(make_install _classic_beta_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Tester 10 1 '{"interface":50600}')"
  eq "not called Forever" "$("$WCC" characters | jq -r '.[0].label')" "Classic Beta"
}

# ------------------------------------------------------------ install-addon

test_install_addon_copies_files() {
  local install
  install=$(make_install _classic_beta_)
  export WCC_EXTRA_DIRS="$install"
  mkdir -p "$install/Interface/AddOns/Questie"
  echo keep >"$install/Interface/AddOns/Questie/file"
  local out
  out=$("$WCC" install-addon)
  eq "reported ok" "$(jq -r '.[0].ok' <<<"$out")" "true"
  eq "toc copied" "$([[ -f $install/Interface/AddOns/WoWCharacterCard/WoWCharacterCard.toc ]] && echo yes)" "yes"
  eq "core copied" "$([[ -f $install/Interface/AddOns/WoWCharacterCard/Core.lua ]] && echo yes)" "yes"
  eq "other addons untouched" "$(cat "$install/Interface/AddOns/Questie/file")" "keep"
}

test_install_addon_replaces_old_copy() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  mkdir -p "$install/Interface/AddOns/WoWCharacterCard"
  echo stale >"$install/Interface/AddOns/WoWCharacterCard/Removed.lua"
  "$WCC" install-addon >/dev/null
  eq "stale file gone" "$([[ -e $install/Interface/AddOns/WoWCharacterCard/Removed.lua ]] && echo yes || echo no)" "no"
}

test_install_addon_every_install() {
  make_install _retail_ >/dev/null
  make_install _classic_beta_ >/dev/null
  export WCC_EXTRA_DIRS="$GAMES"
  eq "both" "$("$WCC" install-addon | jq -r '[.[] | select(.ok)] | length')" "2"
}

test_install_addon_creates_addons_folder() {
  mkdir -p "$GAMES/_retail_/Interface"
  export WCC_EXTRA_DIRS="$GAMES"
  "$WCC" install-addon >/dev/null
  eq "created" "$([[ -d $GAMES/_retail_/Interface/AddOns/WoWCharacterCard ]] && echo yes)" "yes"
}

test_install_addon_refuses_other_folders() {
  mkdir -p "$SANDBOX/documents/Interface"
  local out
  out=$("$WCC" install-addon "$SANDBOX/documents")
  eq "refused" "$(jq -r '.[0].error' <<<"$out")" "not-a-wow-folder"
  eq "nothing written" "$([[ -e $SANDBOX/documents/Interface/AddOns ]] && echo yes || echo no)" "no"
}

test_install_addon_read_only_folder() {
  [[ $EUID -ne 0 ]] || return 0
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  chmod 555 "$install/Interface/AddOns"
  local out
  out=$("$WCC" install-addon 2>/dev/null)
  chmod 755 "$install/Interface/AddOns"
  eq "reported as failed" "$(jq -r '.[0].ok' <<<"$out")" "false"
  eq "says why" "$(jq -r '.[0].error' <<<"$out")" "copy-failed"
  eq "still valid json for every install" "$(jq -r 'length' <<<"$out")" "1"
}

test_install_addon_keeps_saved_data() {
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  "$WCC" install-addon >/dev/null
  eq "data still read" "$("$WCC" characters | jq -r '.[0].name')" "Exampla"
}

test_installs_learned_from_running_game() {
  local install
  install=$(make_install _classic_beta_)
  make_proc 10 WowB.exe 'x -uid wow_classic_beta' "$install" 100
  "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10"
  local out
  out=$("$WCC" installs)
  eq "remembered after game closes" "$(jq -r '.[0].path' <<<"$out")" "$install"
  eq "source" "$(jq -r '.[0].source' <<<"$out")" "running"
  "$WCC" tick >/dev/null
  eq "not listed twice" "$("$WCC" installs | jq length)" "1"
}

test_installs_vanished_folder() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 100
  "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10" "$install"
  eq "left out" "$("$WCC" installs | jq length)" "0"
}

# ----------------------------------------------------------------- sessions

sessions_file() {
  cat "$WCC_STATE_DIR/sessions.jsonl"
}

test_sessions_open_and_update() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 9999000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  WCC_NOW=1000030 "$WCC" tick >/dev/null
  eq "one session" "$(sessions_file | wc -l)" "1"
  eq "start is process start" "$(sessions_file | jq -r .start)" "999990"
  eq "last seen moves" "$(sessions_file | jq -r .last)" "1000030"
  eq "still open" "$(sessions_file | jq -r .end)" "null"
  eq "current seconds" "$(WCC_NOW=1000030 "$WCC" sessions | jq -r .current.seconds)" "40"
}

test_sessions_close_when_game_exits() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10"
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  eq "closed at the poll that noticed" "$(sessions_file | jq -r .end)" "1000015"
  eq "nothing current" "$(WCC_NOW=1000015 "$WCC" sessions | jq -r .current)" "null"
}

test_sessions_close_after_crash_or_power_loss() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10"
  WCC_NOW=1009000 "$WCC" tick >/dev/null
  eq "closed at last seen" "$(sessions_file | jq -r .end)" "1000015"
}

test_sessions_resume_after_shell_restart() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  # The shell was away for a minute; the same game is still running.
  WCC_NOW=1000060 "$WCC" tick >/dev/null
  eq "still one session" "$(sessions_file | wc -l)" "1"
  eq "covers the gap" "$(sessions_file | jq -r .last)" "1000060"
}

test_sessions_reopen_same_process() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  mv "$WCC_PROC_DIR/10" "$SANDBOX/hidden"
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  mv "$SANDBOX/hidden" "$WCC_PROC_DIR/10"
  WCC_NOW=1000030 "$WCC" tick >/dev/null
  eq "not counted twice" "$(sessions_file | wc -l)" "1"
  eq "open again" "$(sessions_file | jq -r .end)" "null"
}

test_sessions_new_game_is_new_session() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10"
  make_proc 20 WoW.exe 'x -uid wow' "$install" 10001000
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  eq "two sessions" "$(sessions_file | wc -l)" "2"
  eq "first closed" "$(sessions_file | head -n 1 | jq -r .end)" "1000015"
  eq "second open" "$(sessions_file | tail -n 1 | jq -r .end)" "null"
}

test_sessions_idle_polls_do_not_write() {
  "$WCC" tick >/dev/null
  eq "no log while nothing has happened" "$([[ -e $WCC_STATE_DIR/sessions.jsonl ]] && echo yes || echo no)" "no"
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  rm -rf "$WCC_PROC_DIR/10"
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  touch -d '2001-01-01' "$WCC_STATE_DIR/sessions.jsonl"
  WCC_NOW=1000030 "$WCC" tick >/dev/null
  eq "unchanged log is not rewritten" "$(date -r "$WCC_STATE_DIR/sessions.jsonl" +%Y)" "2001"
}

test_sessions_skip_damaged_lines() {
  mkdir -p "$WCC_STATE_DIR"
  {
    echo '{"start":999000,"last":999600,"end":999600,"flavor":"_retail_","pid":1,"pstart":1}'
    echo '{"start":999700,"last":9997'
    echo 'not json at all'
    echo '{"start":"bad","last":1,"end":1}'
    echo '{"start":999800,"last":999900,"end":999900,"flavor":"_retail_","pid":2,"pstart":2}'
  } >"$WCC_STATE_DIR/sessions.jsonl"
  eq "good lines counted" "$(WCC_NOW=1000000 "$WCC" sessions | jq -r .week)" "700"
  "$WCC" tick >/dev/null
  eq "damaged lines dropped on next write" "$(sessions_file | wc -l)" "2"
}

# 1000000 is Mon 12 Jan 1970 13:46:40 UTC. Midnight that day is 950400, and it
# is also the start of the week.
test_sessions_totals_split_at_midnight() {
  mkdir -p "$WCC_STATE_DIR"
  {
    # Sunday 23:00 to Monday 01:00: one hour belongs to today and this week.
    echo '{"start":946800,"last":954000,"end":954000,"flavor":"_retail_","pid":1,"pstart":1}'
    # Monday 10:00 to 10:30.
    echo '{"start":986400,"last":988200,"end":988200,"flavor":"_retail_","pid":2,"pstart":2}'
  } >"$WCC_STATE_DIR/sessions.jsonl"
  local out
  out=$(WCC_NOW=1000000 "$WCC" sessions)
  eq "today" "$(jq -r .today <<<"$out")" "5400"
  eq "week starts Monday" "$(jq -r .week <<<"$out")" "5400"
}

test_sessions_week_includes_earlier_days() {
  mkdir -p "$WCC_STATE_DIR"
  # Wednesday 14 Jan 1970 12:00 UTC = 1166400. Monday 10:00 to 11:00 = 986400..990000.
  echo '{"start":986400,"last":990000,"end":990000,"flavor":"_retail_","pid":1,"pstart":1}' >"$WCC_STATE_DIR/sessions.jsonl"
  local out
  out=$(WCC_NOW=1166400 "$WCC" sessions)
  eq "not today" "$(jq -r .today <<<"$out")" "0"
  eq "this week" "$(jq -r .week <<<"$out")" "3600"
}

test_sessions_totals_include_open_session() {
  mkdir -p "$WCC_STATE_DIR"
  echo '{"start":999000,"last":999990,"end":null,"flavor":"_retail_","pid":1,"pstart":1}' >"$WCC_STATE_DIR/sessions.jsonl"
  eq "counted up to now" "$(WCC_NOW=1000000 "$WCC" sessions | jq -r .today)" "1000"
}

test_sessions_local_timezone() {
  mkdir -p "$WCC_STATE_DIR"
  # In Auckland (UTC+12 in January 1970) 1000000 is already Tuesday 01:46.
  # Local midnight was 993600, so only the last 1400 seconds count as today.
  echo '{"start":992600,"last":995000,"end":995000,"flavor":"_retail_","pid":1,"pstart":1}' >"$WCC_STATE_DIR/sessions.jsonl"
  eq "today follows local time" "$(TZ=Pacific/Auckland WCC_NOW=1000000 "$WCC" sessions | jq -r .today)" "1400"
  eq "week follows local time" "$(TZ=Pacific/Auckland WCC_NOW=1000000 "$WCC" sessions | jq -r .week)" "2400"
}

test_sessions_clock_moved_backwards() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  WCC_NOW=999000 "$WCC" tick >/dev/null
  eq "last seen never goes back" "$(sessions_file | jq -r .last)" "1000000"
  local out
  out=$(WCC_NOW=999000 "$WCC" sessions)
  eq "no negative today" "$(jq -r '.today >= 0' <<<"$out")" "true"
  eq "no negative current" "$(jq -r '.current.seconds >= 0' <<<"$out")" "true"
}

test_sessions_old_ones_pruned() {
  mkdir -p "$WCC_STATE_DIR"
  {
    echo '{"start":100,"last":200,"end":200,"flavor":"_retail_","pid":1,"pstart":1}'
    echo '{"start":9999000,"last":9999100,"end":9999100,"flavor":"_retail_","pid":2,"pstart":2}'
  } >"$WCC_STATE_DIR/sessions.jsonl"
  WCC_NOW=10000000 "$WCC" tick >/dev/null
  eq "only the recent one kept" "$(sessions_file | jq -r .start)" "9999000"
}

# ------------------------------------------------------------------- status

test_status_setup_states() {
  eq "no install" "$("$WCC" status | jq -r .setup)" "no-install"
  local install
  install=$(make_install _retail_)
  export WCC_EXTRA_DIRS="$install"
  eq "addon missing" "$("$WCC" status | jq -r .setup)" "addon-missing"
  "$WCC" install-addon >/dev/null
  eq "no data" "$("$WCC" status | jq -r .setup)" "no-data"
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  eq "ready" "$("$WCC" status | jq -r .setup)" "ready"
  sed -i 's/^## Version:.*/## Version: 0.1.0/' "$install/Interface/AddOns/WoWCharacterCard/WoWCharacterCard.toc"
  eq "addon outdated" "$("$WCC" status | jq -r .setup)" "addon-outdated"
}

test_status_shape() {
  local install out
  install=$(make_install _classic_beta_)
  make_proc 10 WowB.exe 'x -uid wow_classic_beta' "$install" 9999000
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  out=$("$WCC" tick)
  eq "ok" "$(jq -r .ok <<<"$out")" "true"
  eq "running" "$(jq -r .running.label <<<"$out")" "Forever"
  eq "session" "$(jq -r .session.seconds <<<"$out")" "10"
  eq "playtime" "$(jq -r .playtime.today <<<"$out")" "10"
  eq "character" "$(jq -r '.characters[0].name' <<<"$out")" "Exampla"
  eq "bundled version" "$(jq -r .addonVersion <<<"$out")" "1.0.0"
}

test_status_does_not_write() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 100
  "$WCC" status >/dev/null
  eq "no session log" "$([[ -e $WCC_STATE_DIR/sessions.jsonl ]] && echo yes || echo no)" "no"
  eq "no installs file" "$([[ -e $WCC_STATE_DIR/installs.json ]] && echo yes || echo no)" "no"
}

test_status_without_jq() {
  local out
  out=$(PATH=/nonexistent /bin/bash "$WCC" status)
  eq "exit code" "$?" "3"
  eq "names the tool" "$(echo "$out" | grep -c 'missing-jq')" "1"
}

test_status_demo_mode() {
  local install out
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 100
  out=$(WCC_DEMO=1 "$WCC" tick)
  eq "made-up character" "$(jq -r '.characters[0].name' <<<"$out")" "Exampla"
  eq "session ends now" "$(jq -r '.session.start + .session.seconds' <<<"$out")" "1000000"
  eq "three characters" "$(jq -r '.characters | length' <<<"$out")" "3"
  eq "writes nothing" "$([[ -e $WCC_STATE_DIR ]] && echo yes || echo no)" "no"
  eq "status matches tick" "$(WCC_DEMO=1 "$WCC" status | jq -r .setup)" "ready"
}

test_sessions_suspend_is_not_play_time() {
  local install
  install=$(make_install _retail_)
  make_proc 10 WoW.exe 'x -uid wow' "$install" 10000000
  WCC_NOW=1000000 "$WCC" tick >/dev/null
  WCC_NOW=1000015 "$WCC" tick >/dev/null
  # The PC slept for eight hours with the game still open.
  WCC_NOW=1028815 "$WCC" tick >/dev/null
  eq "sleep splits the session" "$(sessions_file | wc -l)" "2"
  eq "first ends when last seen" "$(sessions_file | head -n 1 | jq -r .end)" "1000015"
  eq "second starts on waking" "$(sessions_file | tail -n 1 | jq -r .start)" "1028815"
  eq "sleep is not counted" "$(WCC_NOW=1028815 "$WCC" sessions | jq -r .week)" "15"
  WCC_NOW=1028830 "$WCC" tick >/dev/null
  eq "only the newest record moves" "$(sessions_file | head -n 1 | jq -r .end)" "1000015"
  eq "still two sessions" "$(sessions_file | wc -l)" "2"
  eq "counted after waking" "$(WCC_NOW=1028830 "$WCC" sessions | jq -r .week)" "30"
}

test_sessions_day_without_midnight() {
  # In Santiago the clocks go from 23:59 straight to 01:00 on this date, so
  # the day has no midnight.
  local noon
  noon=$(TZ=America/Santiago date -d '2026-09-06 13:00:00' +%s)
  mkdir -p "$WCC_STATE_DIR"
  echo "{\"start\":$((noon - 3600)),\"last\":$noon,\"end\":$noon,\"flavor\":\"_retail_\",\"pid\":1,\"pstart\":1}" >"$WCC_STATE_DIR/sessions.jsonl"
  local out
  out=$(TZ=America/Santiago WCC_NOW=$noon "$WCC" sessions 2>&1)
  eq "today still counted" "$(jq -r .today <<<"$out" 2>/dev/null)" "3600"
  eq "status still prints" "$(TZ=America/Santiago WCC_NOW=$noon "$WCC" status 2>/dev/null | jq -r .ok)" "true"
}

test_status_played_version_without_addon() {
  local retail classic
  retail=$(make_install _retail_)
  classic=$(make_install _classic_)
  export WCC_EXTRA_DIRS="$GAMES"
  "$WCC" install-addon "$retail" >/dev/null
  make_data "$retail" "111#1" "$(character Exampla 42 300)"
  eq "unplayed version is left alone" "$("$WCC" status | jq -r .setup)" "ready"
  mkdir -p "$classic/WTF/Account/111#1"
  eq "played version is offered the addon" "$("$WCC" status | jq -r .setup)" "addon-missing-some"
  eq "install says it was played" "$("$WCC" installs | jq -r '.[] | select(.flavor == "_classic_") | .played')" "true"
  "$WCC" install-addon >/dev/null
  eq "ready once installed" "$("$WCC" status | jq -r .setup)" "ready"
}

test_installs_same_folder_two_spellings() {
  local install
  install=$(make_install _retail_)
  ln -s "$SANDBOX/prefix" "$SANDBOX/link"
  make_proc 10 WoW.exe 'x -uid wow' "$install" 100
  make_data "$install" "111#1" "$(character Exampla 42 300)"
  export WCC_EXTRA_DIRS="$SANDBOX/link/drive_c/Program Files (x86)/World of Warcraft"
  "$WCC" tick >/dev/null
  eq "listed once" "$("$WCC" installs | jq length)" "1"
  eq "character listed once" "$("$WCC" characters | jq length)" "1"
}

test_installs_folder_with_colon() {
  # Wine's own layout: dosdevices/c: points at drive_c.
  GAMES="$SANDBOX/prefix/dosdevices/c:/Program Files (x86)/World of Warcraft"
  make_install _retail_ >/dev/null
  export WCC_WOW_DIR="$GAMES"
  eq "found" "$("$WCC" installs | jq -r '.[0].flavor')" "_retail_"
}

# --------------------------------------------------------------------- main

for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$name"
done

echo "$PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
