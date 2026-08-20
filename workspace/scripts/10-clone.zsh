#!/bin/zsh
#>[what]
#   clone/sync every project of each $GITLAB_GROUPS group into $WORKSPACE_DIR/<host_dir>
#/[what]

emulate -LR zsh
setopt errexit pipefail
umask 002

##[>] 🤖🤖🤖
#[why] glab drives project discovery: without it there is nothing to enumerate
if (( ! $+commands[glab] )) {
  print -r -- "clone: skip: glab not found"
  return 0
}

#[why] one probe covers every mechanism: glab reads its credential from its own config (host) or $GITLAB_TOKEN (image build, CI), and an authenticated api call is the only proof either works. `glab auth status` exits 0 on a rejected token, so it cannot decide this
if { ! glab api /user >/dev/null 2>&1 } {
  print -r -- "clone: skip: glab cannot authenticate (no usable gitlab credential)"
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

function relocate_moved_clones {
  local group=$1 host_dir=$2 gitdir clone origin ns dest
  for gitdir in ${root}/${host_dir}/**/.git(N/); do
    clone=${gitdir:h}
    origin=$(git -C $clone remote get-url origin 2>/dev/null) || continue
    ns=${${${origin##*gitlab.com[:/]}%.git}#/}
    [[ $ns == ${group}/* ]] || continue
    ns=$(glab api "projects/${ns//\//%2F}" 2>/dev/null | jq -r '.path_with_namespace // empty') || continue
    [[ -n $ns ]] || continue
    dest=${root}/${host_dir}/${ns#${group}/}
    [[ $dest == $clone ]] && continue
    if [[ -n "$(git -C $clone status --porcelain)" ]] {
      print -r -- "relocate(skip: dirty): $clone -> $dest"
      continue
    }
    if [[ -e $dest ]] {
      print -r -- "relocate(skip: dest exists): $clone -> $dest"
      continue
    }
    mkdir -p ${dest:h}
    mv $clone $dest
    git -C $dest remote set-url origin ${origin/${origin##*gitlab.com[:/]}/${ns}.git}
    print -r -- "relocate: $clone -> $dest"
  done
}

function remove_empty_shells {
  local dir
  for dir in ${root}/**/assets/data/repo-index.md(N:h:h:h); do
    [[ -d $dir/.git ]] && continue
    local hits=($dir/**/.git(N/))
    (( $#hits )) && continue
    command rm -f $dir/assets/data/repo-index.md $dir/AGENTS.md $dir/CLAUDE.md
    rmdir $dir/assets/data $dir/assets $dir 2>/dev/null
    if [[ -d $dir ]] {
      print -r -- "shell(kept: not empty): $dir"
    } else {
      print -r -- "shell(removed): $dir"
    }
  done
}

#[why] CI has no ssh key: clone over https with the token
typeset url_field=ssh_url_to_repo
if (( ${+CI} )) url_field=http_url_to_repo

typeset pair group host_dir
for pair in $groups; do
  group=${pair%%:*}
  host_dir=${pair#*:}

  relocate_moved_clones $group $host_dir

  glab api --paginate \
    "groups/${group}/projects?include_subgroups=true&archived=false" \
    | jq -r ".[] | select(.marked_for_deletion_on == null) | [.path_with_namespace, .default_branch, .${url_field}] | @tsv" \
    | while IFS=$'\t' read -r ns branch url; do
        local dest_rel=${host_dir}/${ns#${group}/}
        if (( ${+CI} )) url=${url/#https:\/\//https://oauth2:${GITLAB_TOKEN}@}
        if { ! sync_project $dest_rel $branch $url } print -r -- "sync(fail): ${root}/${dest_rel}"
      done
done

remove_empty_shells
##[<] 🤖🤖🤖
