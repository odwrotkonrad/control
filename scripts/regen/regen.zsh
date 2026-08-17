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
  print "  supersede:  close open [automation] prose MRs (except major bumps)"
  print "  branch:     $branch"
  print "  MR title:   $title"
  print "  MR body:    Automated prose regen: $old → $tag ($bump bump)."
  print "  auto-merge: $auto_merge (set at creation, patch/minor only)"
  exit 0
}

#[why] a superseded regen MR is closed, never left for someone to reconcile: its pin is older than the
#   one this run is about to open, so nothing in it is worth landing. a failed one is closed for the
#   same reason and no other, the fresh MR reruns the pipeline from scratch. the failure itself is
#   investigated from the pipeline it already left behind, not by keeping a dead MR open as a reminder
#[why] the [automation] title prefix identifies them, never the branch name: matching prose-v once
#   selected hand-written MRs from three unrelated repos, any of which this would then have closed
#[why] a major bump is deliberately left for a human: never close what someone has been asked to read
stale=$(glab api "projects/$group%2F$repo/merge_requests?state=opened&per_page=100" \
  | yq -r '.[] | select(.title | test("^.automation. chore.prose.:")) | select(.title | test("→ v[0-9]+[.]0[.]0$") | not) | [.iid, .title] | @tsv')
if [[ -n $stale ]] {
  while IFS=$'\t' read -r iid stale_title; do
    [[ -n $iid ]] || continue
    glab api -X PUT "projects/$group%2F$repo/merge_requests/$iid" -f state_event=close >/dev/null \
      && print "$repo: closed superseded !$iid ($stale_title)" \
      || print "$repo: could not close superseded !$iid ($stale_title)"
  done <<< $stale
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
#[why] --auto-merge on the create call, not a merge request afterwards: gitlab attaches the pipeline a
#   second or two after the MR exists, so every after-the-fact arming attempt races that gap and gets
#   a 405. set at creation the flag is part of the same request and there is no gap to lose
mr_args=(--title "$title" --description "Automated prose regen: $old → $tag ($bump bump)." --source-branch $branch --repo $group/$repo --remove-source-branch --yes)
[[ $auto_merge == yes ]] && mr_args+=(--auto-merge)
glab mr create $mr_args

#[why] auto-merge only holds an MR whose pipeline is still running: one that already finished green
#   has nothing left to wait on, and gitlab declines to arm rather than merging. a docs-only regen
#   pipeline finishes in well under a minute, so this is the common case, not the edge one
#[why] the merge api directly, not `glab mr merge`: that path demands a sha it will not look up
#   itself, failing with "SHA must be provided when merging". yq parses the json, the ci image having
#   no jq
#[why] merging unguarded is reserved for a repo that provably runs no merge-request pipeline: a slow,
#   queued or failing pipeline must never be mistaken for an absent one and merged past. anything this
#   declines to merge is left open and reported, so a red regen is something a human sees rather than
#   something that silently merged or silently stalled
outcome=""
if [[ $auto_merge == yes ]] {
  mr_iid=$(glab api "projects/$group%2F$repo/merge_requests?source_branch=$branch&state=opened" | yq -r '.[0].iid')
  mr_api="projects/$group%2F$repo/merge_requests/$mr_iid"
  mr=$(glab api $mr_api)
  if [[ $(print -r -- "$mr" | yq -r '.merge_when_pipeline_succeeds // false') == true ]] {
    outcome="auto-merge armed"
  } else {
    pipeline_status=$(print -r -- "$mr" | yq -r '.head_pipeline.status // "none"')
    case $pipeline_status in
      success|none)
        if glab api -X PUT "$mr_api/merge" -f sha=$(print -r -- "$mr" | yq -r '.sha') \
             -f should_remove_source_branch=true; then
          [[ $pipeline_status == none ]] \
            && outcome="merged (repo runs no merge-request pipeline)" \
            || outcome="merged (pipeline already green)"
        else
          outcome="LEFT OPEN: merge refused, merge status $(print -r -- "$mr" | yq -r '.detailed_merge_status // "unknown"')"
        fi ;;
      #[why] --auto-merge at creation does not always stick: gitlab attaches the pipeline a moment
      #   after the MR exists, and an arming request that lands in that gap is refused. Retry here
      #   until gitlab accepts, then confirm the flag is actually set rather than trusting the call.
      #   Without this an MR whose pipeline goes green seconds later sits open forever, which is how
      #   resume-md-pdf!25 ended up mergeable, green and unmerged
      *)
        for _ in {1..15}; do
          glab api -X PUT "$mr_api/merge" -f sha=$(print -r -- "$mr" | yq -r '.sha') \
            -f merge_when_pipeline_succeeds=true -f should_remove_source_branch=true >/dev/null 2>&1
          mr=$(glab api $mr_api)
          [[ $(print -r -- "$mr" | yq -r '.merge_when_pipeline_succeeds // false') == true ]] && break
          #[why] the pipeline can finish green while we are still trying to arm: merge it outright
          #   rather than arming a wait that has nothing left to wait for
          if [[ $(print -r -- "$mr" | yq -r '.head_pipeline.status // "none"') == success ]] {
            glab api -X PUT "$mr_api/merge" -f sha=$(print -r -- "$mr" | yq -r '.sha') \
              -f should_remove_source_branch=true >/dev/null 2>&1
            break
          }
          sleep 2
        done
        mr=$(glab api $mr_api)
        if [[ $(print -r -- "$mr" | yq -r '.merge_when_pipeline_succeeds // false') == true ]] {
          outcome="auto-merge armed (pipeline $pipeline_status)"
        } elif [[ $(print -r -- "$mr" | yq -r '.state') == merged ]] {
          outcome="merged (pipeline went green while arming)"
        } else {
          outcome="LEFT OPEN: could not arm auto-merge, pipeline is $(print -r -- "$mr" | yq -r '.head_pipeline.status // "none"'), merge status $(print -r -- "$mr" | yq -r '.detailed_merge_status // "unknown"')"
        } ;;
    esac
  }
} else {
  outcome="major bump, awaiting human review"
}
print "$repo: regen MR opened ($old → $tag): $outcome"
##[<] 🤖🤖🤖
