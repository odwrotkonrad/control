#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
graph=$repo_root/deps/deps-graph.yml
ci_image='$ARTIFACT_REGISTRY/ci-linux:$CI_IMAGES_REF'
runner_tag=gke-linux-amd64

zparseopts -D -E -- -graph:=o_graph -produces:=o_prod -consumes:=o_cons -affected:=o_aff -emit-pipeline:=o_emit
(( ${#o_graph} )) && graph=${o_graph[2]}

repos=(${(f)"$(yq '.repositories[].repo' $graph)"})
edges=(${(f)"$(yq '.edges // {} | to_entries[] | .key + " " + (.value | join(","))' $graph)"})

vertex_repo() {
  local v=$1
  while true; {
    if (( ${repos[(I)$v]} )) {
      print $v
      return 0
    }
    [[ $v == */* ]] || return 1
    v=${v%/*}
  }
}

affected() {
  local u=$1 up downs v r
  local -aU hits
  for line in $edges; {
    up=${line%% *}
    [[ $up == $u || $up == $u/* ]] || continue
    downs=${line#* }
    for v in ${(s:,:)downs}; {
      r=$(vertex_repo $v) || continue
      [[ $r == $u || $u == $r/* ]] && continue
      hits+=($r)
    }
  }
  (( ${#hits} )) && print -l ${(o)hits}
  return 0
}

if (( ${#o_prod} )) {
  REPO=${o_prod[2]} yq '.repositories[] | select(.repo == env(REPO)) | .artifacts[].name' $graph
  exit 0
}

if (( ${#o_cons} )) {
  r=${o_cons[2]}
  local -aU ups
  for line in $edges; {
    downs=${line#* }
    for v in ${(s:,:)downs}; {
      if [[ $v == $r || $v == $r/* ]] ups+=(${line%% *})
    }
  }
  (( ${#ups} )) && print -l ${(o)ups}
  exit 0
}

if (( ${#o_aff} )) {
  affected ${o_aff[2]}
  exit 0
}

#[why] the producer is a parameter, not always prose: che-packages publishes a catalog go-modules
#   pins, and the same fan-out has to carry that version too. PRODUCER defaults to prose so the
#   prose tag bridge keeps working unchanged, and PROSE_TAG stays accepted as its alias
producer=${PRODUCER:-prose}
tag=${RELEASE_TAG:-${PROSE_TAG:-}}
[[ -n $tag ]] || { print -ru2 -- "RELEASE_TAG (or PROSE_TAG) unset and no query flag given"; exit 1 }
prev=${RELEASE_PREV_TAG:-${PROSE_PREV_TAG:-}}

#[why] the artifact, not the repo: a repo that publishes several things has one edge per artifact,
#   and only the consumers of the released one should be regenerated
work=(${(f)"$(affected ${PRODUCER_ARTIFACT:-$producer})"})

#[why] the version lives in one place, infra/iac's tfvars, published as a group variable every
#   consumer's pipeline reads. a consumer rendered at the new tag before that variable moved would
#   fail its own docsgen check (its CI renders at the old value), so the pin lands first and every
#   content regen waits for the variable to carry the tag before it renders
pin_repo=infra/iac
has_pin=0
(( ${work[(Ie)$pin_repo]} )) && has_pin=1

if (( ${#o_emit} )) {
  {
    print 'stages: [pin, regen]'
    print 'variables:'
    print '  ARTIFACT_REGISTRY: $GRP_KO_VAR_ARTIFACT_REGISTRY'
    print '  CI_IMAGES_REF: $GRP_KO_VAR_CI_IMAGES_REF'
    if (( ${#work} )) {
      for r in $work; {
        print "regen:$r:"
        print "  image: $ci_image"
        print '  tags:'
        print "    - $runner_tag"
        print '  variables:'
        print '    CONTROL_GITLAB_TOKEN: $REPO_VAR_CONTROL_GITLAB_TOKEN'
        if [[ $r == $pin_repo ]] {
          print '  stage: pin'
        } else {
          print '  stage: regen'
          (( has_pin )) && print "  needs: [\"regen:$pin_repo\"]"
        }
        print '  script:'
        if [[ $r != $pin_repo ]] && (( has_pin )) {
          print "    - scripts/regen/wait-ref.zsh --producer $producer --tag $tag"
        }
        print -n "    - scripts/regen/regen.zsh --repo $r --tag $tag --producer $producer"
        [[ -n $prev ]] && print -n " --prev $prev"
        print ''
      }
    } else {
      print 'no-pinned-downstreams:'
      print "  image: $ci_image"
      print '  tags:'
      print "    - $runner_tag"
      print '  script:'
      print "    - echo '$producer $tag: no affected downstreams'"
    }
  } > ${o_emit[2]}
  print "wrote ${o_emit[2]} (${#work} downstream(s): ${work:-none})"
} else {
  (( ${#work} )) && print -l $work
}
##[<] 🤖🤖🤖
