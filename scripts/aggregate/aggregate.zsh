#!/usr/bin/env zsh
##[>] 🤖🤖🤖
set -euo pipefail

repo_root=${0:a:h:h:h}
group=konradodwrot
seed_file=$repo_root/deps/seed-interfaces.yml
graph_file=$repo_root/deps/deps-graph.yml
iface_path=.repo/cross-repo-interface.yml

local_ws="" out=$graph_file check=0
zparseopts -D -E -- -local:=o_local -out:=o_out -check=o_check
(( ${#o_local} )) && local_ws=${o_local[2]}
(( ${#o_out} )) && out=${o_out[2]}
(( ${#o_check} )) && check=1

tmp=$(mktemp -d)
trap 'command rm -rf $tmp' EXIT

cp $seed_file $tmp/combined.yml

seed_repos=(${(f)"$(yq '.repos | keys | .[]' $seed_file)"})

declared_repos=()
if [[ -n $local_ws ]] {
  for f in $local_ws/**/$iface_path(N); {
    declared_repos+=(${${f%/$iface_path}#$local_ws/})
  }
} else {
  declared_repos=(${(f)"$(curl -fsS "https://gitlab.com/api/v4/groups/$group/projects?include_subgroups=true&per_page=100" \
    | yq -p json '.[].path_with_namespace' | sed "s|^$group/||")"})
}

typeset -U candidates
candidates=($seed_repos $declared_repos)

fetched_repos=()
for repo in ${(o)candidates}; {
  if [[ -n $local_ws ]] {
    [[ -f $local_ws/$repo/$iface_path ]] || continue
    grep -v '^\s*#' $local_ws/$repo/$iface_path > $tmp/iface.yml
  } else {
    curl -fsS "https://gitlab.com/api/v4/projects/$group%2F${repo//\//%2F}/repository/files/${iface_path//\//%2F}/raw?ref=main" \
      2>/dev/null | grep -v '^\s*#' > $tmp/iface.yml || continue
    [[ -s $tmp/iface.yml ]] || continue
  }
  REPO=$repo IFACE=$tmp/iface.yml yq -i '.repos.[env(REPO)] = load(env(IFACE))' $tmp/combined.yml
  fetched_repos+=($repo)
}

all_repos=(${(f)"$(yq '.repos | keys | .[]' $tmp/combined.yml)"})

produced=()
missing=()
typeset -A edge_downs
consumed_lines=()
for repo in ${(o)all_repos}; {
  for name in ${(f)"$(REPO=$repo yq '.repos.[env(REPO)].downstream // [] | .[].name' $tmp/combined.yml)"}; {
    produced+=("$repo/$name")
  }
  for up in ${(f)"$(REPO=$repo yq '.repos.[env(REPO)].upstream // [] | .[]' $tmp/combined.yml)"}; {
    edge_downs[$up]+=" $repo"
    consumed_lines+=("$repo $up")
  }
  for pair in ${(f)"$(REPO=$repo yq '.repos.[env(REPO)].edges // {} | to_entries[] | .key + "|" + (.value | join(","))' $tmp/combined.yml)"}; {
    up=${pair%%\|*}
    for artifact in ${(s:,:)${pair#*\|}}; {
      edge_downs[$up]+=" $repo/$artifact"
      consumed_lines+=("$repo $up")
      if (( ! ${produced[(I)$repo/$artifact]} )) missing+=("$repo edge into $artifact, which $repo does not produce")
    }
  }
}

for line in $consumed_lines; {
  vertex=${line#* }
  if (( ! ${produced[(I)$vertex]} )) missing+=("${line%% *} consumes $vertex, which no repo produces")
}
if (( ${#missing} )) {
  print -l "inconsistent interfaces:" ${(u)missing} >&2
  exit 1
}

{
  print '##[>] 🤖'
  yq '{"repositories": (.repos | to_entries | sort_by(.key) | map({"repo": .key, "artifacts": (.value.downstream // [])}))}' $tmp/combined.yml
  print 'edges:'
  for up in ${(ok)edge_downs}; {
    print "  $up:"
    for v in ${(ou)${=edge_downs[$up]}}; print "    - $v"
  }
  print '##[<] 🤖'
} > $tmp/graph.yml

if (( check )) {
  if ! { diff -u $graph_file $tmp/graph.yml } {
    print "deps/deps-graph.yml drifted, rerun scripts/aggregate/aggregate.zsh (diff above)" >&2
    exit 1
  }
  print "deps-graph in sync (declared: ${fetched_repos:-none}, seeded: $(( ${#candidates} - ${#fetched_repos} )) repos)"
} else {
  cp $tmp/graph.yml $out
  print "wrote $out (declared: ${fetched_repos:-none}, seeded: $(( ${#candidates} - ${#fetched_repos} )) repos)"
}
##[<] 🤖🤖🤖
