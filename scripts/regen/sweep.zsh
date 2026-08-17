#!/usr/bin/env zsh
##[>] 🤖🤖
# Land regen MRs that missed their auto-merge window. regen.zsh arms
# merge_when_pipeline_succeeds seconds after opening an MR, which GitLab
# refuses while the pipeline does not yet exist or the MR is briefly
# unmergeable. Those MRs sit open forever with nothing revisiting them.
#
# Sweeps every open prose-v* regen MR across the group: arms auto-merge where
# the pipeline is still running, merges where it already went green, and leaves
# red ones open. Safe to re-run: arming an armed MR and merging a merged one
# are both no-ops.
#
# Usage: sweep.zsh [--group <group>] [--dry-run]
emulate -LR zsh
setopt errexit pipefail

group=konradodwrot
dry=0
while (( $# )); do
  case $1 in
    --group) group=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) print -ru2 -- "usage: sweep.zsh [--group <group>] [--dry-run]"; exit 2 ;;
  esac
done

#[why] the group-wide MR listing, not a per-repo loop: the fan-out's repo set lives in the
#   pipeline that created it, and a sweep run later has no memory of which repos took part
#[why] every candidate is filtered on the [automation] title prefix below, never on a branch
#   name: source_branch_search matches loosely, and filtering on prose-v returned hand-written
#   MRs from three unrelated repos, any of which this would then have merged
mrs=$(glab api "groups/${group}/merge_requests?state=opened&per_page=100")

count=$(print -r -- "$mrs" | yq -r 'length')
(( count )) || { print -r -- "sweep: no open prose regen MRs"; exit 0 }

for i in {0..$(( count - 1 ))}; do
  project_id=$(print -r -- "$mrs" | yq -r ".[$i].project_id")
  iid=$(print -r -- "$mrs" | yq -r ".[$i].iid")
  title=$(print -r -- "$mrs" | yq -r ".[$i].title")
  mr_api="projects/${project_id}/merge_requests/${iid}"

  mr=$(glab api "$mr_api")
  armed=$(print -r -- "$mr" | yq -r '.merge_when_pipeline_succeeds // false')
  pipe_status=$(print -r -- "$mr" | yq -r '.head_pipeline.status // "none"')
  mergeable=$(print -r -- "$mr" | yq -r '.detailed_merge_status // "unknown"')
  sha=$(print -r -- "$mr" | yq -r '.sha')
  label="${title} (project ${project_id} !${iid})"

  #[why] the marker automation stamps on its own MRs: anything without it is a person's work
  if [[ $title != "[automation] "* ]] {
    continue
  }

  #[why] a major bump waits for a human by design: never sweep what regen deliberately left alone
  if [[ $title == *"→ v"*".0.0"* ]] {
    print -r -- "skip  $label: major bump, human review"
    continue
  }
  if [[ $armed == true ]] {
    print -r -- "ok    $label: already armed"
    continue
  }
  case $pipe_status in
    success)
      action="merge (pipeline green)" ;;
    running|pending|created|waiting_for_resource|preparing|scheduled)
      action="arm auto-merge (pipeline $pipe_status)" ;;
    failed|canceled)
      print -r -- "leave $label: pipeline $pipe_status, needs a human"
      continue ;;
    *)
      print -r -- "leave $label: pipeline $pipe_status, merge status $mergeable"
      continue ;;
  esac

  if (( dry )) {
    print -r -- "DRY   $label: would $action"
    continue
  }

  if [[ $pipe_status == success ]] {
    if glab api -X PUT "$mr_api/merge" -f sha=$sha -f should_remove_source_branch=true; then
      print -r -- "merged $label"
    else
      print -r -- "leave $label: merge refused, merge status $mergeable"
    fi
  } else {
    if glab api -X PUT "$mr_api/merge" -f sha=$sha \
         -f merge_when_pipeline_succeeds=true -f should_remove_source_branch=true; then
      print -r -- "armed $label"
    else
      print -r -- "leave $label: auto-merge refused, merge status $mergeable"
    fi
  }
done
##[<] 🤖🤖
