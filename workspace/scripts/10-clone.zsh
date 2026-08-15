#!/bin/zsh
#>[what]
#   clone/sync every project of each $GITLAB_GROUPS group into $WORKSPACE_DIR/<host_dir>
#/[what]

emulate -LR zsh
setopt errexit pipefail
umask 002

##[>] 🤖🤖🤖
#[why] token required: authenticates gitlab (CI sets it, clones over https).
if [[ -z ${GITLAB_TOKEN-} ]] {
  print -r -- "clone: skip: GITLAB_TOKEN unset"
  return 0
}

#[what] parse $GITLAB_GROUPS: ';'/newline-separated <group>:<host_dir> pairs, empty host_dir -> group
typeset -a groups
if [[ -n ${GITLAB_GROUPS-} ]] {
  typeset entry group host_dir
  for entry in ${(s.;.)${GITLAB_GROUPS//$'\n'/;}}; do
    entry=${entry## }; entry=${entry%% }
    [[ -z $entry ]] && continue
    group=${entry%%:*}
    host_dir=${entry#*:}
    [[ $host_dir == $entry || -z $host_dir ]] && host_dir=$group
    groups+=("${group}:${host_dir}")
  done
} elif [[ -n ${GITLAB_GROUP-} ]] {
  groups+=("${GITLAB_GROUP}:${HOST_DIR_GITLAB_GROUP:-$GITLAB_GROUP}")
}

if (( ! $#groups )) {
  print -r -- "clone: skip: no group in GITLAB_GROUPS/GITLAB_GROUP"
  return 0
}

typeset root=${WORKSPACE_DIR:-$HOME/projects/gitlab}

function sync_project {
  local ns=$1 branch=$2 url=$3
  local dest=${root}/${ns}

  if [[ -z $branch ]] branch=main

  if [[ ! -d ${dest}/.git ]] {
    mkdir -p ${dest:h}
    git clone --quiet $url $dest 2> >(grep -v 'cloned an empty repository' >&2)
    print -r -- "clone(new): $dest"
    return 0
  }

  git -C $dest fetch --prune origin

  if { ! git -C $dest rev-parse --verify --quiet origin/$branch >/dev/null } {
    print -r -- "skip(no-remote-branch): $dest"
    return 0
  }

  if [[ -n "$(git -C $dest status --porcelain)" ]] {
    print -r -- "skip(dirty): $dest"
    return 0
  }

  if [[ "$(git -C $dest symbolic-ref --short HEAD)" != $branch ]] git -C $dest switch $branch

  local before=$(git -C $dest rev-parse HEAD)

  if { ! git -C $dest merge --ff-only origin/$branch } {
    print -r -- "skip(diverged): $dest"
    return 0
  }

  if [[ "$(git -C $dest rev-parse HEAD)" == $before ]] {
    print -r -- "sync(no-changes): $dest"
    return 0
  }

  print -r -- "sync(updated): $dest"
}

#[why] CI has no ssh key: clone over https with the token
typeset url_field=ssh_url_to_repo
if (( ${+CI} )) url_field=http_url_to_repo

typeset pair group host_dir
for pair in $groups; do
  group=${pair%%:*}
  host_dir=${pair#*:}

  glab api --paginate \
    "groups/${group}/projects?include_subgroups=true&archived=false" \
    | jq -r ".[] | select(.marked_for_deletion_on == null) | [.path_with_namespace, .default_branch, .${url_field}] | @tsv" \
    | while IFS=$'\t' read -r ns branch url; do
        local dest_rel=${host_dir}/${ns#${group}/}
        if (( ${+CI} )) url=${url/#https:\/\//https://oauth2:${GITLAB_TOKEN}@}
        if { ! sync_project $dest_rel $branch $url } print -r -- "sync(fail): ${root}/${dest_rel}"
      done
done
##[<] 🤖🤖🤖
