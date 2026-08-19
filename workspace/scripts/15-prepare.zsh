#!/bin/zsh
#>[what]
#   run each cloned repo's repo-prepare-dev-env, turning clones into working
#   checkouts before 20-index reads the purpose docs they generate
#/[what]

emulate -LR zsh
setopt pipefail
umask 002

##[>] 🤖🤖🤖
#[why] environments without make (image bakes) skip
if (( ! $+commands[make] )) {
  print -r -- "prepare: skip: make not found"
  return 0
}

typeset root=${WORKSPACE_DIR:-$HOME/projects/gitlab}

#[why] no errexit and an explicit success at the end: one unpreparable repo must never abort a
#   session bootstrap or an image build, so every failure is reported and the pass continues
typeset repo out
for repo in ${root}/**/.git(N/:h); do
  if [[ ! -f ${repo}/Makefile ]] {
    print -r -- "prepare: skip(no makefile): $repo"
    continue
  }
  #[why] probe with -n: a repo that has not adopted the convention is skipped, not failed
  if { ! make -C $repo -n repo-prepare-dev-env >/dev/null 2>&1 } {
    print -r -- "prepare: skip(no target): $repo"
    continue
  }
  #[why] output captured, not discarded: a success stays one quiet line, while a failure prints what
  #   went wrong. a report saying only that a repo failed sends the reader back to run it by hand
  if { out=$(make -C $repo repo-prepare-dev-env 2>&1) } {
    print -r -- "prepare: $repo"
  } else {
    print -r -- "prepare(fail): $repo"
    print -r -- ${(F)${(f)out}/#/    }
  }
done

return 0
##[<] 🤖🤖🤖
