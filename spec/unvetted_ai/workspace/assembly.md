# Feature: Local Workspace Assembly

<!-- [>] 🤖🤖 -->

The `workspace/` che profile assembles the local workspace (canonical home
here, moved from configs' `gitlab/projects`): cloning the group tree,
linking parent Makefiles and the VS Code workspace file onto the host, and
generating the non-checked-out subgroup indexes.

Scenario: a fresh host gets every workspace repo with one profile run
  Status: implemented
  Given `$GITLAB_GROUPS` group-to-dir pairs and a `$GITLAB_TOKEN`
  When the profile's clone script runs
  Then every non-archived project of each group is cloned into `$WORKSPACE_DIR` mirroring the group tree
  And existing clean checkouts fast-forward, dirty or diverged ones are skipped and reported

Scenario: every subgroup dir carries a fresh generated index
  Status: implemented
  Given cloned repos under `$WORKSPACE_DIR`
  When the profile's index script runs
  Then each subgroup dir gets `assets/data/repo-index.md` plus rendered `AGENTS.md`/`CLAUDE.md`
  And none of these generated files is checked into any repo

Scenario: parent dirs delegate child-repo targets
  Status: implemented
  Given the profile's `tree/` parent Makefiles linked onto the workspace parents
  When `make <repo>-<target>` runs from a parent dir
  Then it delegates into the child repo without cd-ing there

Scenario: the VS Code workspace file lists every workspace repo
  Status: implemented
  Given the workspace file in the profile's `tree/`
  When a repo is added to or removed from the workspace
  Then the file is edited here, its canonical home

<!-- [<] 🤖🤖 -->
