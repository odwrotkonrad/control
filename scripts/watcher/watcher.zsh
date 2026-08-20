#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
group=konradodwrot
#[why] consumers carry no pin: each che.yml reads PROSE_REF from its env, and infra/iac's tfvars is the
#   one line that declares the current value. the watcher reads that authority, falls back to the
#   newest tag when iac is not checked out, and keeps every repo's gitignored .env at it
ref_pattern='env\.PROSE_REF'
authority_pattern='^prose_ref *= *"(v[0-9]+\.[0-9]+\.[0-9]+)"'
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
  pin=""
  for line in ${(f)"$(cat $workspace/infra/iac/tf/terraform.tfvars 2>/dev/null)"}; {
    [[ $line =~ $authority_pattern ]] || continue
    pin=$match[1]
    break
  }
  if [[ -z $pin ]] {
    pin=$latest
    print "prose ref: ${pin:-none} (no infra/iac checkout, using the latest tag)"
  } else {
    print "prose ref: $pin (infra/iac tfvars)"
    if [[ -n $latest && $pin != $latest ]] print "prose ref $pin behind latest $latest (regen MR flow owns the bump)"
  }
  [[ -n $pin ]] || return 0
  for chefile in $workspace/*/che.yml(N) $workspace/*/*/che.yml(N); {
    repo=${${chefile:h}#$workspace/}
    if ! rg -q "$ref_pattern" $chefile ${chefile:h}/.repo/che.yml(N) 2>/dev/null; then
      print "$repo: no prose ref, no-op"
      continue
    fi
    stamp_file=$state_dir/${repo//\//__}
    stamp=$(cat $stamp_file 2>/dev/null || true)
    if [[ $pin == $stamp ]] {
      print "$repo: at $pin, outputs fresh"
      continue
    }
    print "$repo: ref $pin (last rendered: ${stamp:-never}), refreshing .env and non-checked-out outputs"
    upsert_env ${chefile:h}/.env PROSE_REF $pin
    if ! { (cd ${chefile:h} && PROSE_REF=$pin che render-templates --profiles=ontoRepo) } {
      print "$repo: render failed, keeping stamp, skipping"
      continue
    }
    tracked=(${(f)"$(git -C ${chefile:h} diff --name-only)"})
    (( ${#tracked} )) && git -C ${chefile:h} checkout -- $tracked
    print $pin > $stamp_file
  }
}

#[why] .env is gitignored, so the watcher may rewrite it: che's mergeUpsert keeps an existing key,
#   which is right for a user's own values and wrong for a version that must track the authority
upsert_env() {
  local file=$1 key=$2 value=$3
  if [[ -f $file ]] && grep -q "^$key=" $file; then
    sed -i.bak -E "s|^$key=.*|$key=$value|" $file && command rm -f $file.bak
  else
    print "$key=$value" >> $file
  fi
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
