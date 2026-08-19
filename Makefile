##[>] 🤖🤖
#[what] Project's Makefile
SHELL := zsh

WRAPPERS := repo-prepare-dev-env
COMMANDS := semver-next tag-mint render-templates aggregate aggregate-check repo-ci-prepare-hooks repo-ci-precommit-all

.PHONY: $(WRAPPERS) $(COMMANDS)

##[>] Dev Environment [genai-include]
#[why] render precedes hooks: the docsgen pre-commit hook runs render-templates and fails on drift,
#   so a fresh clone whose generated files were never rendered would fail its first commit
#[what] make a fresh clone a working checkout: generated docs, git hooks
repo-prepare-dev-env: render-templates repo-ci-prepare-hooks
##[<] Dev Environment

##[>] Docs [genai-include]
#[what] render *.ontoRepo.tpl onto the repo (makefile.agents.md, repo-structure.md, CLAUDE.md, AGENTS.md)
render-templates:
	@che render-templates --profiles=ontoRepo
##[<] Docs

##[>] Graph [genai-include]
#[what] aggregate per-repo cross-repo-interface declarations over the seeds into deps/deps-graph.yml
aggregate:
	@scripts/aggregate/aggregate.zsh

#[what] fail if deps/deps-graph.yml drifted from the aggregated interfaces
aggregate-check:
	@scripts/aggregate/aggregate.zsh --check
##[<] Graph

##[>] Release [genai-include]
#[what] print the next semver tag inferred from the last tag..HEAD diff (override: `semver: major|minor|patch` commit token)
semver-next: render-templates
	@ci/semver-bump.zsh

#[what] mint and push the next semver tag (CI: authed via TAG_TOKEN)
tag-mint: render-templates
	@ci/tag-mint.zsh
##[<] Release

##[>] CI [genai-include]
#[what] install lefthook git hooks
repo-ci-prepare-hooks:
	@lefthook install --force

#[what] run pre-commit hooks over all files (not just staged)
repo-ci-precommit-all: repo-ci-prepare-hooks
	@lefthook run pre-commit --all-files --force
##[<] CI
##[<] 🤖🤖
