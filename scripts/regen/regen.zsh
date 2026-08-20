#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

group=konradodwrot

repo="" tag="" prev="" workdir="" producer=prose dry=0
zparseopts -D -E -- -repo:=o_repo -tag:=o_tag -prev:=o_prev -workdir:=o_wd -producer:=o_prod -dry-run=o_dry
(( ${#o_repo} )) && repo=${o_repo[2]}
(( ${#o_tag} )) && tag=${o_tag[2]}
(( ${#o_prev} )) && prev=${o_prev[2]}
(( ${#o_wd} )) && workdir=${o_wd[2]}
(( ${#o_prod} )) && producer=${o_prod[2]}
(( ${#o_dry} )) && dry=1

[[ -n $repo && -n $tag ]] || { print "usage: regen.zsh --repo <repo> --tag <vX.Y.Z> [--prev <tag>] [--workdir <dir>] [--producer <name>] [--dry-run]" >&2; exit 2 }

#[why] every slash encoded, not just the group separator: a subgroup repo like infra/iac made
#   "$group%2F$repo" into konradodwrot%2Finfra/iac, whose inner slash GitLab reads as a path
#   segment, so every merge_requests call 404'd and the regen died after cloning
project_path=${${group}//\//%2F}%2F${repo//\//%2F}

if [[ -z $workdir ]] {
  if (( dry )) {
    print "regen --dry-run needs --workdir <checkout> (no clone in dry-run)" >&2
    exit 2
  }
  workdir=$(mktemp -d)/$repo:t
  git clone --depth 1 https://control-maintainer:${CONTROL_GITLAB_TOKEN:?}@gitlab.com/$group/$repo.git $workdir
}

#[why] each producer writes its version somewhere different in its own format: prose into a che.yml
#   remote-source ref, che-packages into a pin env file read by the vendor step. The producer
#   selects which files to look in and which pattern names the version
#[why] found by content, not from a fixed file list: configs pins prose in .repo/che.yml and again
#   in profiles/llm/claude/che.yml, and a list naming only the first two left the third at v0.0.4
#   while the repo moved to v0.0.22. A pin the fan-out does not look at is a pin that rots
case $producer in
  #[why] one tfvars line in infra/iac, published as the GRP_KO_VAR_PROSE_REF group variable: every
  #   consumer reads PROSE_REF from its environment, so a consumer carries no pin to move. a consumer
  #   regen is content-only: render at the new tag, commit what changed
  prose)
    pin_glob='*.tfvars'
    pin_pattern='prose_ref *= *"(v[0-9]+\.[0-9]+\.[0-9]+)"'
    export PROSE_REF=$tag ;;
  #[why] a tfvars line, not the old che/packages-pin.env: that pin lived inside the che module, so
  #   raising it matched release-che's `changes: [che/**/*]` rule and cut a che release for a
  #   catalog-only change. the version now reaches every repo as the CHE_PACKAGES_REF group CI
  #   variable, and infra/iac's tfvars is the one file that declares its value
  che-packages)
    pin_glob='*.tfvars'
    pin_pattern='che_packages_ref *= *"v?([0-9]+\.[0-9]+\.[0-9]+)"' ;;
  oci-images)
    pin_glob='*.tfvars'
    pin_pattern='ci_images_ref *= *"(latest|v?[0-9]+\.[0-9]+\.[0-9]+)"' ;;
  *)
    print -ru2 -- "regen: unknown producer $producer"
    exit 2 ;;
esac

#[why] the checkout's tracked files only: a build artefact or a vendored copy carrying the same
#   string is not this repo's pin to move
spec_files=()
for f in ${(f)"$(cd $workdir && git ls-files -- $pin_glob '**/'$pin_glob 2>/dev/null)"}; {
  [[ -f $workdir/$f ]] || continue
  grep -qE -- "$pin_pattern" $workdir/$f 2>/dev/null && spec_files+=($workdir/$f)
}

content_only=0
if (( ! ${#spec_files} )) {
  if [[ $producer == prose ]] {
    content_only=1
  } else {
    print "$repo: no $producer pin file, nothing to regen"
    exit 0
  }
}

old=""
if (( ! content_only )) {
  for f in $spec_files; {
    for line in ${(f)"$(<$f)"}; {
      [[ $line =~ $pin_pattern ]] || continue
      old=$match[1]
      break 2
    }
  }
  if [[ -z $old ]] {
    print "$repo: no $producer pin found, nothing to regen"
    exit 0
  }
}

if (( content_only )) {
  shown_tag=$tag
  bump=patch
  old=${prev:-none}
} elif [[ $old != v* && $old != [0-9]* ]] {
  #[why] a non-semver seed carries no format to copy and no parts to compare: it spells the tag as
  #   the producer publishes it and counts as a major bump, so the first raise off it is reviewed
  shown_tag=$tag
  bump=major
} else {
  #[why] the tag as this repo spells its pin: $old carries the format, so the same release reads as
  #   v0.0.14 for prose and 0.0.14 for che-packages, matching what the file will hold
  shown_tag=${tag#v}
  if [[ $old == v* ]] shown_tag=v$shown_tag
}

#[why] compared bare: prose writes the ref with a leading v, che-packages a bare version in tfvars,
#   so "$old == $tag" put 0.0.13 against v0.0.13 and never matched. an already-current pin would
#   open a no-op MR titled "0.0.13 → v0.0.13"
if (( ! content_only )) && [[ ${old#v} == ${tag#v} ]] {
  print "$repo: already pinned to $shown_tag"
  exit 0
}

if [[ -z ${bump:-} ]] {
  old_parts=(${(s:.:)${old#v}})
  new_parts=(${(s:.:)${tag#v}})
  bump=patch
  (( new_parts[2] != old_parts[2] )) && bump=minor
  (( new_parts[1] != old_parts[1] )) && bump=major
}

#[why] the [automation] prefix is how other automation finds these MRs: matching a branch-name
#   pattern instead once selected hand-written MRs from three unrelated repos
#[why] a content-only regen moves no pin, so "old → new" would name a transition the repo never
#   had: it is a docs-gen MR rendered at the producer's tag, titled as such
if (( content_only )) {
  scope=docs-gen
  branch=docs-gen-$producer-$shown_tag
  title="[automation] chore(docs-gen): render at $producer $shown_tag"
  body="Automated docs regen: rendered at $producer $shown_tag."
} else {
  scope=$producer
  branch=$producer-$shown_tag
  title="[automation] chore($producer): $old → $shown_tag"
  body="Automated $producer regen: $old → $shown_tag ($bump bump)."
}
auto_merge=$([[ $bump == major ]] && print no || print yes)

if (( dry )) {
  print "DRY RUN: regen plan for $repo"
  print "  pin:        $old → $shown_tag ($bump bump)"
  print "  render:     make render-templates in $workdir"
  print "  supersede:  close open [automation] $producer MRs (except major bumps)"
  print "  branch:     $branch"
  print "  MR title:   $title"
  print "  MR body:    $body"
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
#[why] this closes other people's merge requests, so the match is literal and anchored: [automation]
#   as real brackets, the producer as an exact name, both from the start of the title. The earlier
#   pattern spelled them as . wildcards and matched "Xautomation. choreXproseX:", a title no
#   automation wrote. Nothing without the prefix, and nothing belonging to another producer, is
#   eligible to be closed here
#[why] the producer is interpolated by the shell, not passed via env(): yq does not evaluate env()
#   as a regex inside test(), so the pattern was empty and matched every title, hand-written ones
#   included
stale=$(glab api "projects/$project_path/merge_requests?state=opened&per_page=100" \
  | yq -r ".[] | select(.title | test(\"^\\\\[automation\\\\] chore\\\\(${scope}\\\\): \")) | select(.title | test(\"→ v[0-9]+[.]0[.]0\$\") | not) | [.iid, .title] | @tsv")
if [[ -n $stale ]] {
  while IFS=$'\t' read -r iid stale_title; do
    [[ -n $iid ]] || continue
    glab api -X PUT "projects/$project_path/merge_requests/$iid" -f state_event=close >/dev/null \
      && print "$repo: closed superseded !$iid ($stale_title)" \
      || print "$repo: could not close superseded !$iid ($stale_title)"
  done <<< $stale
}

cd $workdir
for f in ${spec_files#$workdir/}; {
  #[why] the pin is written back in the producer's own format: prose carries the leading v in the
  #   ref, che-packages a bare version in a quoted tfvars string
  case $producer in
    prose)
      sed -i.pinbak -E "s|(prose_ref[[:space:]]*=[[:space:]]*\")v?[0-9]+\.[0-9]+\.[0-9]+\"|\1$tag\"|g" $f ;;
    che-packages)
      sed -i.pinbak -E "s|(che_packages_ref[[:space:]]*=[[:space:]]*\")v?[0-9]+\.[0-9]+\.[0-9]+\"|\1${tag#v}\"|g" $f ;;
    oci-images)
      sed -i.pinbak -E "s|(ci_images_ref[[:space:]]*=[[:space:]]*\")(latest\|v?[0-9]+\.[0-9]+\.[0-9]+)\"|\1$tag\"|g" $f ;;
  esac
  command rm -f $f.pinbak
}
#[why] pick the target the repo actually defines, rather than running one and falling back on
#   failure: only configs names it repo-render-templates, every other repo names it
#   render-templates. The old `render-templates || repo-render-templates` masked any real render
#   failure behind "No rule to make target 'repo-render-templates'", so the cause was invisible
render_target=render-templates
make -n repo-render-templates >/dev/null 2>&1 && render_target=repo-render-templates
print -r -- "regen: rendering via make $render_target"
make $render_target
git checkout -b $branch
git add -A
#[why] a content-only regen may find the release changed nothing this repo renders: an empty commit
#   would fail, and an MR carrying no diff is noise
if git diff --cached --quiet; then
  print "$repo: nothing rendered differently at $shown_tag, no MR"
  exit 0
fi
#[why] the ci container carries no git identity and the commit is the bot's, not a person's: name it from the
#   job's own identity so the regen MR's authorship points back at the pipeline that opened it
git -c user.name="${GITLAB_USER_NAME:-control-maintainer}" -c user.email="${GITLAB_USER_EMAIL:-control-maintainer@noreply.gitlab.com}" commit -m "$title"
git push -u origin $branch
#[why] --auto-merge on the create call, not a merge request afterwards: gitlab attaches the pipeline a
#   second or two after the MR exists, so every after-the-fact arming attempt races that gap and gets
#   a 405. set at creation the flag is part of the same request and there is no gap to lose
mr_args=(--title "$title" --description "$body" --source-branch $branch --repo $group/$repo --remove-source-branch --yes)
[[ $auto_merge == yes ]] && mr_args+=(--auto-merge)
#[why] a failed create is not fatal here: when --auto-merge cannot be armed glab still creates the
#   MR, then exits non-zero, and under set -e that killed the job before the arming retry below ever
#   ran. The MR existed, correct and unarmed, while the pipeline reported failure. Whether the MR is
#   really there is decided by looking it up, not by this exit code
glab mr create $mr_args || print -r -- "regen: mr create reported failure, checking whether the MR exists"

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
  mr_iid=$(glab api "projects/$project_path/merge_requests?source_branch=$branch&state=opened" | yq -r '.[0].iid')
  if [[ -z $mr_iid || $mr_iid == null ]] {
    print -ru2 -- "$repo: no open MR for $branch, create really did fail"
    exit 1
  }
  mr_api="projects/$project_path/merge_requests/$mr_iid"
  mr=$(glab api $mr_api)
  if [[ $(print -r -- "$mr" | yq -r '.merge_when_pipeline_succeeds // false') == true ]] {
    outcome="auto-merge armed"
  } else {
    #[why] a freshly created MR has no head_pipeline yet, so "none" means "not attached yet" far
    #   more often than "this repo runs no merge-request pipeline". Treating the two alike sent
    #   every fan-out MR down the unguarded-merge path, where gitlab refused the merge because the
    #   pipeline was still pending, and the MR was reported LEFT OPEN having never been armed.
    #   Wait for the pipeline to appear before deciding which case this is
    for _ in {1..30}; do
      [[ $(print -r -- "$mr" | yq -r '.head_pipeline.id // "null"') != null ]] && break
      sleep 2
      mr=$(glab api $mr_api)
    done
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
print "$repo: regen MR opened ($old → $shown_tag): $outcome"
##[<] 🤖🤖🤖
