# Feature: Aggregated Repo Dependency Graph

<!-- [>] 🤖🤖 -->

One generated graph names every repo, the artifacts it produces, and the
dependency edges between them: the supplementary data prerelease preference
and prose propagation resolve against. A vertex is `repo/artifact`. The graph
is never hand-maintained: each repo declares its own surface in
`.repo/cross-repo-interface.yml` (`upstream:` first: consumed vertices as
`<repo>/<artifact>` strings, or `{consumes: <vertex>, into: <artifact>}` when
the dependency embeds into a specific produced artifact; then `downstream:`
produced artifacts as `name:` + `type:`, types so far:
`binary | go-module | oci-image | che-profile | ai-prose | lockfile | pdf | dataset`). Aggregation merges all declarations over
bootstrap seeds (`deps/seed-interfaces.yml`, shrinking as repos declare) and
renders `deps/deps-graph.yml`: two arrays, `repositories:` (vertices) and
`dependencies:` (edges grouped by upstream, downstream entries a bare
`<repo>` when consumed by the repo's pipeline or worktree, `<repo>/<artifact>`
when embedded). Canonical generated file: `deps/deps-graph.yml`.

Scenario: a downstream pipeline knows which upstreams to check for prereleases
  Status: todo
  Given the generated graph lists repos and grouped upstream→downstream edges
  When a repo's MR pipeline resolves its dependencies
  Then it reads its upstreams from the graph, not from per-repo config

Scenario: a human or agent sees the whole workspace dependency structure in one place
  Status: implemented
  Given the generated graph file
  When anyone asks what depends on what
  Then one file answers it: vertices in `repositories:`, edges in `dependencies:`

Scenario: prerelease preference resolves per artifact, not per repo
  Status: todo
  Given a repo producing multiple artifacts (e.g. `go-modules`: `che`, `lib`)
  When a downstream pipeline resolves an upstream prerelease
  Then it picks the prerelease of the exact artifact vertex it depends on
  And other artifacts of the same upstream repo stay untouched

Scenario: the graph never drifts from the declarations
  Status: implemented
  Given per-repo interface declarations and the committed generated graph
  When CI re-aggregates and compares
  Then any drift fails the check

Scenario: a dangling declaration fails aggregation
  Status: implemented
  Given an `upstream:` entry naming an artifact no repo produces
  When aggregation runs
  Then it fails naming the consumer and the missing artifact

<!-- [<] 🤖🤖 -->
