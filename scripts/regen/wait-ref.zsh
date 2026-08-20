#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

group=konradodwrot
producer="" tag="" timeout=1800
zparseopts -D -E -- -producer:=o_prod -tag:=o_tag -timeout:=o_to
(( ${#o_prod} )) && producer=${o_prod[2]}
(( ${#o_tag} )) && tag=${o_tag[2]}
(( ${#o_to} )) && timeout=${o_to[2]}
[[ -n $producer && -n $tag ]] || { print "usage: wait-ref.zsh --producer <name> --tag <tag> [--timeout <seconds>]" >&2; exit 2 }

case $producer in
  prose) key=GRP_KO_VAR_PROSE_REF ;;
  che-packages) key=GRP_KO_VAR_CHE_PACKAGES_REF ;;
  oci-images) key=GRP_KO_VAR_CI_IMAGES_REF ;;
  *) print -ru2 -- "wait-ref: unknown producer $producer"; exit 2 ;;
esac

#[why] the job token glab falls back to in CI cannot read group variables: the maintainer token the
#   regen already clones with can
export GITLAB_TOKEN=${CONTROL_GITLAB_TOKEN:?}

#[why] the pin MR auto-merges, then infra/iac's main pipeline applies it: only then does the group
#   variable carry the tag, and only then does a consumer's own CI render at the same version this
#   regen is about to commit. compared bare so v0.0.14 and 0.0.14 read as one version
deadline=$(( $(date +%s) + timeout ))
while true; {
  current=$(glab variable get -g $group $key 2>/dev/null || true)
  if [[ ${current#v} == ${tag#v} ]] {
    print "wait-ref: $key is $current"
    exit 0
  }
  if (( $(date +%s) >= deadline )) {
    print -ru2 -- "wait-ref: $key still $current after ${timeout}s, wanted $tag"
    exit 1
  }
  print "wait-ref: $key is ${current:-unset}, waiting for $tag"
  sleep 30
}
##[<] 🤖🤖🤖
