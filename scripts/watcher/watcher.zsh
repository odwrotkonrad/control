#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
group=konradodwrot
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/prose-watcher

typeset -A pin_repo=(
  PROSE_ASSETS_REF cross-repo/prose/assets
  PROSE_SPEC_REF   cross-repo/prose/spec
  MISC_REF         cross-repo/misc
)
typeset -A pin_key=(
  PROSE_ASSETS_REF prose_assets_ref
  PROSE_SPEC_REF   prose_spec_ref
  MISC_REF         misc_ref
)
pin_vars=(PROSE_ASSETS_REF PROSE_SPEC_REF MISC_REF)

workspace=${repo_root:h:h} interval=300 once=0
zparseopts -D -E -- -workspace:=o_ws -interval:=o_int -once=o_once
(( ${#o_ws} )) && workspace=${o_ws[2]}
(( ${#o_int} )) && interval=${o_int[2]}
(( ${#o_once} )) && once=1

mkdir -p $state_dir

latest_tag() {
  git ls-remote --tags https://gitlab.com/$group/$1.git 'v*' \
    | awk -F/ '{print $NF}' | grep -v '\^{}' | sort -V | tail -1 || true
}

authority_pin() {
  local key=$1 line
  for line in ${(f)"$(cat $workspace/cross-repo/infra/iac/tf/terraform.tfvars 2>/dev/null)"}; {
    [[ $line =~ "^$key *= *\"(v[0-9]+\.[0-9]+\.[0-9]+)\"" ]] || continue
    print $match[1]
    return 0
  }
  return 1
}

pass() {
  local var pin latest chefile repo stamp_file stamp
  local -A pins
  for var in $pin_vars; {
    latest=$(latest_tag $pin_repo[$var])
    if pin=$(authority_pin $pin_key[$var]); then
      print "$var: $pin (iac tfvars, latest tag ${latest:-none})"
    else
      pin=$latest
      print "$var: ${pin:-none} (no iac checkout, using the latest tag)"
    fi
    [[ -n $pin ]] && pins[$var]=$pin
  }
  (( ${#pins} )) || return 0
  local fingerprint=${(j:,:)${(k)pins/(#m)*/$MATCH=$pins[$MATCH]}}
  for chefile in $workspace/**/che.yml(N); {
    [[ $chefile == */.user/* ]] && continue
    repo=${${chefile:h}#$workspace/}
    if ! rg -q 'env\.(PROSE_ASSETS_REF|PROSE_SPEC_REF|MISC_REF)' $chefile ${chefile:h}/.repo/che.yml(N) 2>/dev/null; then
      continue
    fi
    stamp_file=$state_dir/${repo//\//__}
    stamp=$(cat $stamp_file 2>/dev/null || true)
    if [[ $fingerprint == $stamp ]] {
      print "$repo: outputs fresh"
      continue
    }
    print "$repo: pins moved (last rendered: ${stamp:-never}), refreshing .env and non-checked-out outputs"
    for var in ${(k)pins}; upsert_env ${chefile:h}/.env $var $pins[$var]
    if ! { (cd ${chefile:h} && env ${(k)pins/(#m)*/$MATCH=$pins[$MATCH]} che render-templates --profiles=ontoRepo) } {
      print "$repo: render failed, keeping stamp, skipping"
      continue
    }
    tracked=(${(f)"$(git -C ${chefile:h} diff --name-only)"})
    (( ${#tracked} )) && git -C ${chefile:h} checkout -- $tracked
    print $fingerprint > $stamp_file
  }
}

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
