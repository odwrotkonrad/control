# Purpose

## What It Is

Cross-repo automation hub: reacts to prose releases, owns the generated dependency graph aggregated from per-repo `.repo/cross-repo-interface.yml` declarations, regenerates affected downstreams as deterministic bot MRs (auto-merge on patch/minor, human review on major), and ships a local watcher that keeps non-checked-out rendered outputs fresh in local worktrees.

## Why It Exists

Centralized prose needs an operator: something must notice a prose release, know who consumes it, and carry the update into every affected repo. The dependency graph was hand-maintained in one spec file; here each repo declares its own interface and control derives the graph, so the map never drifts from the territory.

## Goals

- Prose tag → triggered pipeline → verify affected downstreams → fan out regen MRs.
- Dependency graph generated, never hand-edited: per-repo declarations merged over bootstrap seeds, inconsistency fails the build.
- Bot MRs deterministic and safe: fixed text template, auto-merge only patch/minor on green downstream CI.
- Local sync: the watcher re-renders only gitignored outputs, tracked files change via MRs only.
- Workspace assembly lives here: the `workspace/` che profile clones the group tree, links parent Makefiles and the VS Code workspace file, and generates the non-checked-out repo indexes.
