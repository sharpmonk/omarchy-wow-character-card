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
  unset WCC_EXTRA_DIRS
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
  make_data "$forever" "111#1" "$(character Sharpmonk 42 300)"
  make_data "$forever" "222#2" "$(character Bankalt 5 200)"
  eq "most recent first" "$("$WCC" characters | jq -r '[.[].name] | join(",")')" "Sharpmonk,Bankalt,Oldmain"
  eq "version label attached" "$("$WCC" characters | jq -r '.[0].label')" "Forever"
}

test_characters_same_name_in_two_versions() {
  local retail forever
  retail=$(make_install _retail_)
  forever=$(make_install _classic_beta_)
  export WCC_EXTRA_DIRS="$GAMES"
  make_data "$retail" "111#1" "$(character Sharpmonk 80 100)"
  make_data "$forever" "111#1" "$(character Sharpmonk 42 300)"
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
  make_data "$install" "111#1" "$(character Sharpmonk 42 300 '{"xp":610,"xpMax":1000,"rested":180,"money":3124005,"session":{"startedAt":1,"startLevel":40,"xpGained":900,"moneyDelta":-10250}}')"
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
  make_data "$install" "111#1" "$(character Sharpmonk 42 300)"
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
  make_data "$install" "111#1" "$(character Sharpmonk 42 300)"
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
  make_data "$install" "111#1" "$(character Sharpmonk 42 300)"
  "$WCC" install-addon >/dev/null
  eq "data still read" "$("$WCC" characters | jq -r '.[0].name')" "Sharpmonk"
}

# --------------------------------------------------------------------- main

for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$name"
done

echo "$PASSED passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
