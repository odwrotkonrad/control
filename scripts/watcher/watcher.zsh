#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
group=konradodwrot
pin_pattern='@[^ "]*prose[^ "]*#v[0-9]+\.[0-9]+\.[0-9]+'
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/prose-watcher

workspace=${repo_root:h} interval=300 once=0
zparseopts -D -E -- -workspace:=o_ws -interval:=o_int -once=o_once
(( ${#o_ws} )) && workspace=${o_ws[2]}
(( ${#o_int} )) && interval=${o_int[2]}
(( ${#o_once} )) && once=1

mkdir -p $state_dir

pass() {
  local latest chefile repo pin stamp_file stamp
  latest=$(git ls-remote --tags https://gitlab.com/$group/prose.git 'v*' \
    | awk -F/ '{print $NF}' | grep -v '\^{}' | sort -V | tail -1 || true)
  print "latest prose tag: ${latest:-none}"
  for chefile in $workspace/*/che.yml(N) $workspace/*/*/che.yml(N); {
    repo=${${chefile:h}#$workspace/}
    pin=$(rg -o "$pin_pattern" $chefile 2>/dev/null | rg -o 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -z $pin ]] {
      print "$repo: no prose pin, no-op"
      continue
    }
    stamp_file=$state_dir/${repo//\//__}
    stamp=$(cat $stamp_file 2>/dev/null || true)
    if [[ $pin == $stamp ]] {
      print "$repo: pinned $pin, outputs fresh"
    } else {
      print "$repo: pin $pin (last rendered: ${stamp:-never}), refreshing non-checked-out outputs"
      (cd ${chefile:h} && che render-templates)
      tracked=(${(f)"$(git -C ${chefile:h} diff --name-only)"})
      (( ${#tracked} )) && git -C ${chefile:h} checkout -- $tracked
      print $pin > $stamp_file
    }
    if [[ -n $latest && $pin != $latest ]] print "$repo: pinned $pin behind latest $latest (regen MR flow owns the bump)"
  }
}

if (( once )) {
  pass
} else {
  while true; {
    pass
    sleep $interval
  }
}
##[<] 🤖🤖🤖
