#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
graph=$repo_root/deps/deps-graph.yml
ci_image=registry.gitlab.com/konradodwrot/infra/oci-images/ci-linux:latest
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

tag=${PROSE_TAG:?PROSE_TAG unset and no query flag given}
prev=${PROSE_PREV_TAG:-}
work=(${(f)"$(affected prose)"})

if (( ${#o_emit} )) {
  {
    if (( ${#work} )) {
      for r in $work; {
        print "regen:$r:"
        print "  image: $ci_image"
        print '  tags:'
        print "    - $runner_tag"
        print '  script:'
        print -n "    - scripts/regen/regen.zsh --repo $r --tag $tag"
        [[ -n $prev ]] && print -n " --prev $prev"
        print ''
      }
    } else {
      print 'no-pinned-downstreams:'
      print "  image: $ci_image"
      print '  tags:'
      print "    - $runner_tag"
      print '  script:'
      print "    - echo 'prose $tag: no affected downstreams'"
    }
  } > ${o_emit[2]}
  print "wrote ${o_emit[2]} (${#work} downstream(s): ${work:-none})"
} else {
  (( ${#work} )) && print -l $work
}
##[<] 🤖🤖🤖
