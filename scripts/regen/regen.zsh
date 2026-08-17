#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

group=konradodwrot

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

old=""
for f in $spec_files; {
  for line in ${(f)"$(<$f)"}; {
    [[ $line =~ 'prose[^ "]*\?ref=(v[0-9]+\.[0-9]+\.[0-9]+)' ]] || continue
    old=$match[1]
    break 2
  }
}
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
#[why] the [automation] prefix is how other automation finds these MRs: matching a branch-name
#   pattern instead once selected hand-written MRs from three unrelated repos
title="[automation] chore(prose): $old → $tag"
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
#[why] regen commits tracked docs, and no tracked doc carries a secret: the op:// refs live in
#   gitignored local .env templates a repo renders for its developers. this job holds no 1Password
#   credentials, so resolving them is both impossible and pointless, and iac's ontoRepo profile
#   rendering .env alongside its docs failed the whole render on the first op:// ref it met
export CHE_RENDER_TEMPLATES_SKIP_SECRETS=true
make render-templates 2>/dev/null || make repo-render-templates
git checkout -b $branch
git add -A
#[why] the ci container carries no git identity and the commit is the bot's, not a person's: name it from the
#   job's own identity so the regen MR's authorship points back at the pipeline that opened it
git -c user.name="${GITLAB_USER_NAME:-control-maintainer}" -c user.email="${GITLAB_USER_EMAIL:-control-maintainer@noreply.gitlab.com}" commit -m "$title"
git push -u origin $branch
mr_args=(--title "$title" --description "Automated prose regen: $old → $tag ($bump bump)." --source-branch $branch --repo $group/$repo --yes)
glab mr create $mr_args

#[why] --auto-merge needs the MR's pipeline to exist: gitlab creates it a second or two after the MR
#   itself, and asking to merge before it appears makes gitlab reject the request outright (405) and
#   leaves the regen MR sitting open. poll until it shows up, then merge on green
#[why] the merge api directly, not `glab mr merge`: that path demands a sha it will not look up
#   itself, failing with "SHA must be provided when merging". yq parses the json, the ci image having
#   no jq
#[why] the unguarded merge is reserved for a repo that provably runs no merge-request pipeline: a
#   slow, queued or failing pipeline must never be mistaken for an absent one and merged past. when
#   auto-merge cannot be armed and a pipeline does exist, the MR is left open and reported, so a red
#   regen is something a human sees rather than something that silently merged or silently stalled
outcome=""
if [[ $auto_merge == yes ]] {
  mr_iid=$(glab api "projects/$group%2F$repo/merge_requests?source_branch=$branch&state=opened" | yq -r '.[0].iid')
  mr_api="projects/$group%2F$repo/merge_requests/$mr_iid"
  armed=0
  for _ in {1..30}; do
    sha=$(glab api $mr_api | yq -r '.sha')
    if glab api -X PUT "$mr_api/merge" -f sha=$sha \
         -f merge_when_pipeline_succeeds=true -f should_remove_source_branch=true; then
      armed=1
      break
    fi
    sleep 2
  done
  if (( armed )) {
    outcome="auto-merge armed"
  } else {
    pipeline_id=$(glab api $mr_api | yq -r '.head_pipeline.id // ""')
    if [[ -z $pipeline_id || $pipeline_id == null ]] {
      glab api -X PUT "$mr_api/merge" -f sha=$(glab api $mr_api | yq -r '.sha') \
        -f should_remove_source_branch=true
      outcome="merged (repo runs no merge-request pipeline)"
    } else {
      pipeline_status=$(glab api $mr_api | yq -r '.head_pipeline.status // "unknown"')
      outcome="LEFT OPEN: auto-merge refused, pipeline $pipeline_id is $pipeline_status"
    }
  }
} else {
  outcome="major bump, awaiting human review"
}
print "$repo: regen MR opened ($old → $tag): $outcome"
##[<] 🤖🤖🤖
