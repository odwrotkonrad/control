#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

group=konradodwrot
pin_pattern='@[^ "]*prose[^ "]*\?ref=v[0-9]+\.[0-9]+\.[0-9]+'

repo="" tag="" prev="" workdir="" dry=0
zparseopts -D -E -- -repo:=o_repo -tag:=o_tag -prev:=o_prev -workdir:=o_wd -dry-run=o_dry
(( ${#o_repo} )) && repo=${o_repo[2]}
(( ${#o_tag} )) && tag=${o_tag[2]}
(( ${#o_prev} )) && prev=${o_prev[2]}
(( ${#o_wd} )) && workdir=${o_wd[2]}
(( ${#o_dry} )) && dry=1

[[ -n $repo && -n $tag ]] || { print "usage: regen.zsh --repo <repo> --tag <vX.Y.Z> [--prev <tag>] [--workdir <dir>] [--dry-run]" >&2; exit 2 }

if [[ -z $workdir ]] {
  if (( dry )) {
    print "regen --dry-run needs --workdir <checkout> (no clone in dry-run)" >&2
    exit 2
  }
  workdir=$(mktemp -d)/$repo:t
  git clone --depth 1 https://control-maintainer:${CONTROL_GITLAB_TOKEN:?}@gitlab.com/$group/$repo.git $workdir
}

spec_files=($workdir/che.yml(N) $workdir/.repo/che.yml(N))
if (( ! ${#spec_files} )) {
  print "$repo: no che.yml, nothing to regen"
  exit 0
}

old=$(rg -o --no-filename "$pin_pattern" $spec_files 2>/dev/null | rg -o 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ -z $old ]] {
  print "$repo: no prose pin in che.yml, nothing to regen"
  exit 0
}

if [[ $old == $tag ]] {
  print "$repo: already pinned to $tag"
  exit 0
}

old_parts=(${(s:.:)${old#v}})
new_parts=(${(s:.:)${tag#v}})
bump=patch
(( new_parts[2] != old_parts[2] )) && bump=minor
(( new_parts[1] != old_parts[1] )) && bump=major

branch=prose-$tag
title="chore(prose): $old → $tag"
auto_merge=$([[ $bump == major ]] && print no || print yes)

if (( dry )) {
  print "DRY RUN: regen plan for $repo"
  print "  pin:        $old → $tag ($bump bump)"
  print "  render:     make render-templates in $workdir"
  print "  branch:     $branch"
  print "  MR title:   $title"
  print "  MR body:    Automated prose regen: $old → $tag ($bump bump)."
  print "  auto-merge: $auto_merge (patch/minor only, on green pipeline)"
  exit 0
}

cd $workdir
for f in ${spec_files#$workdir/}; {
  sed -i.prosebak -E "s|(prose[^ \"]*\?ref=)v[0-9]+\.[0-9]+\.[0-9]+|\1$tag|g" $f
  command rm -f $f.prosebak
}
make render-templates 2>/dev/null || make repo-render-templates
git checkout -b $branch
git add -A
git commit -m "$title"
git push -u origin $branch
mr_args=(--title "$title" --description "Automated prose regen: $old → $tag ($bump bump)." --source-branch $branch --repo $group/$repo --yes)
glab mr create $mr_args
[[ $auto_merge == yes ]] && glab mr merge $branch --repo $group/$repo --auto-merge --remove-source-branch --yes
print "$repo: regen MR opened ($old → $tag, auto-merge: $auto_merge)"
##[<] 🤖🤖🤖
