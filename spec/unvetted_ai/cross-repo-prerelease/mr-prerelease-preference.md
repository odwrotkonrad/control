# Feature: Cross-Repo MR Prerelease Preference

<!-- [>] 🤖🤖 -->

Dependent MRs across repos pick up each other's results before merge: an open
MR with a passing prerelease stage publishes a prerelease, and downstream MRs
prefer that prerelease over the latest release.

Scenario: an upstream MR author shares buildable results before merging
  Status: todo
  Given an open MR in a producing repo (e.g. `go-modules/che`)
  When its pipeline's prerelease stage passes
  Then a prerelease of the MR's artifacts is published under a prerelease version
  And the prerelease is discoverable by the MR it came from

Scenario: a downstream MR consumes upstream work without waiting for its merge
  Status: todo
  Given an open upstream MR with a passing prerelease stage
  And a downstream MR in a consuming repo (e.g. `configs`) depending on that work
  When the downstream MR's pipeline resolves the upstream dependency
  Then it prefers the upstream MR's prerelease over the latest release

Scenario: a downstream MR never picks up unverified upstream work
  Status: todo
  Given an upstream MR that is closed, merged, or whose prerelease stage has not passed
  When the downstream MR's pipeline resolves the upstream dependency
  Then it falls back to the latest release

<!-- [<] 🤖🤖 -->
