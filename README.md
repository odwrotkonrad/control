# Control

Cross-repo automation: prose propagation, dependency graph, regen MRs, local sync.

## Purpose

Reacts to [prose](https://gitlab.com/konradodwrot/prose) releases: a prose tag triggers this repo's pipeline, which aggregates the dependency graph, resolves affected downstreams, and fans out regen jobs, each opening a deterministic MR that bumps the downstream's prose pin and re-renders its docs. Patch and minor MRs auto-merge on green CI; major waits for a human.

## Dependency graph

Each repo declares its own surface in `.repo/cross-repo-interface.yml`: `upstream:` consumed `<repo>/<artifact>` vertices (repo-level consumption: pipeline, worktree), `edges:` a map of upstream vertex to the list of this repo's artifacts it lands in (`go-modules/lib: [che]`), then `downstream:` produced artifacts (`name` + `type`). `scripts/aggregate/aggregate.zsh` fetches every declaration (raw GitLab API, no clones), merges them over `deps/seed-interfaces.yml` (bootstrap entries for repos not declaring yet), and renders `deps/deps-graph.yml`: generated, committed for readability, drift-checked in CI, never hand-edited. A consumed artifact nobody produces, or an edge into an artifact the repo does not produce, fails aggregation.

## Workspace assembly

`workspace/` is the che profile assembling the local workspace (moved here from configs' `gitlab/projects`): `scripts/10-clone.zsh` clones/syncs every project of each `$GITLAB_GROUPS` group into `$WORKSPACE_DIR`, `scripts/20-index.zsh` generates each subgroup's repo-index and rendered `AGENTS.md`/`CLAUDE.md` (all non-checked-out outputs), `tree/` carries the parent Makefiles and the VS Code workspace file linked onto the host. Profile names stay `gitlab/projects` / `gitlab/projects-parent-links` so host wiring repoints without renames.

## Scripts

- `scripts/aggregate/`: build `deps/deps-graph.yml` from interfaces (`--local <workspace>` offline, `--check` drift gate).
- `scripts/verify/`: queries over the graph (`--produces <repo>`, `--consumes <repo>`, `--affected <vertex>`), plus `--emit-pipeline` writing the regen child pipeline for a `PROSE_TAG`.
- `scripts/regen/`: per-downstream regen: bump prose pin, `make render-templates`, branch, MR, auto-merge when the bump is at most minor. `--dry-run --workdir <checkout>` prints the plan.
- `scripts/watcher/`: local poller refreshing only non-checked-out (gitignored) rendered outputs per worktree; tracked files change via the MR flow only.

## License

[MIT](LICENSE)
