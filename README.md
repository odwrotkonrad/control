# Control

Cross-repo automation: prose propagation, dependency graph, regen MRs, local sync.

## Purpose

### What It Is

Cross-repo automation hub. Reacts to prose releases, owns the dependency graph aggregated from per-repo `.repo/cross-repo-interface.yml` declarations, regenerates affected downstreams as deterministic bot MRs (auto-merge on patch/minor, human review on major), and runs a local watcher that keeps non-checked-out rendered outputs fresh in local worktrees.

### Why It Exists

Centralized prose needs an operator: something to notice a release, know who consumes it, and carry the update into every affected repo. The dependency graph used to be hand-maintained in one spec file. Now each repo declares its own interface and control derives the graph, so the map cannot drift from the territory.

### Goals

- A prose tag triggers a pipeline, which verifies affected downstreams, then fans out regen MRs.
- Dependency graph generated, never hand-edited: per-repo declarations merged over bootstrap seeds, inconsistency fails the build.
- Bot MRs deterministic and safe: fixed text template, auto-merge only patch/minor on green downstream CI.
- Local sync: the watcher re-renders only gitignored outputs, tracked files change via MRs only.
- Workspace assembly lives here: the `workspace/` che profile clones the group tree, links parent Makefiles and the VS Code workspace file, generates the non-checked-out repo indexes.

## Dependency graph

Each repo declares its own surface in `.repo/cross-repo-interface.yml`: `upstream:` consumed `<repo>/<artifact>` vertices (repo-level consumption: pipeline, worktree), `edges:` a map of upstream vertex to the list of this repo's artifacts it lands in (`go-modules/lib: [che]`), then `downstream:` produced artifacts (`name` + `type`). `scripts/aggregate/aggregate.zsh` fetches every declaration (raw GitLab API, no clones), merges them over `deps/seed-interfaces.yml` (bootstrap entries for repos not declaring yet), and renders `deps/deps-graph.yml`: generated, committed for readability, drift-checked in CI, never hand-edited. A consumed artifact nobody produces, or an edge into an artifact the repo does not produce, fails aggregation.

## Workspace assembly

`workspace/` is the che profile assembling the local workspace (moved here from configs' `gitlab/projects`): `scripts/10-clone.zsh` clones/syncs every project of each `$GITLAB_GROUPS` group into `$WORKSPACE_DIR`, `scripts/20-index.zsh` generates each subgroup's repo-index and rendered `AGENTS.md`/`CLAUDE.md` (all non-checked-out outputs), `tree/` carries the parent Makefiles and the VS Code workspace file linked onto the host. Profile names stay `gitlab/projects` / `gitlab/projects-parent-links` so host wiring repoints without renames.

## Scripts

- `scripts/aggregate/`: build `deps/deps-graph.yml` from interfaces (`--local <workspace>` offline, `--check` drift gate).
- `scripts/verify/`: queries over the graph (`--produces <repo>`, `--consumes <repo>`, `--affected <vertex>`), plus `--emit-pipeline` writing the regen child pipeline for a `PROSE_TAG`.
- `scripts/regen/`: per-downstream regen: bump prose pin, `make render-templates`, branch, MR, auto-merge when the bump is at most minor. `--dry-run --workdir <checkout>` prints the plan.
- `scripts/watcher/`: local poller refreshing only non-checked-out (gitignored) rendered outputs per worktree. Tracked files change via the MR flow only.

## License

[MIT](LICENSE)
