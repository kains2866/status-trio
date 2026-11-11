# Personal Fork Release Implementation Plan

> **For agentic workers:** Use `executing-plans` for the release preparation and `requesting-code-review` before integration. Check off each verified step.

**Goal:** Publish the current personal Status Trio changes and microphone fix as version 1.9.3 (build 50) in `kains2866/status-trio`.

**Architecture:** Reuse the manual frozen-SHA release pipeline. Keep Universal packaging, Xcode 27, SDK 26+, Helper contracts, the reviewed `distribution` environment, and artifact-only publication. Point the fork's update feed and Sparkle verification key to its own repository.

**Tech Stack:** Swift/SwiftUI, Sparkle Ed25519, shell/Ruby release tooling, GitHub Actions and `gh`.

**Spec:** User requested commit/push and explicitly selected “构建并发布 GitHub Release”; release boundaries are in `AGENTS.md` and `.agents/rules/release.md`.

## Global Constraints

- macOS 13 minimum; SDK 26 or newer; Xcode 27 release runner.
- One frozen lowercase 40-character candidate SHA on `main`; Universal arm64 + x86_64 package.
- Preserve personal panel behavior; never weaken or skip a failing assertion.
- Preserve `distribution` human review; never print or commit private keys.
- Main App and Helper signatures, manifest, tag, appcast and public asset must agree.
- Report Ad-hoc signing honestly when Developer ID/notarization credentials are absent.

## Review Focus

- The fork must never publish assets or updates to the upstream repository.
- The embedded Sparkle public key must verify updates signed by this fork's secret.
- Exact raster failures must be diagnosed before changing any baseline.
- Existing source/main worktrees and the running Personal development app must remain independent.
- Publication must use the verified artifact and frozen SHA, including any recovery.

## Task 1: Commit the microphone fix

- [x] Re-run focused quick profile; 262 XCTest + 12 Swift Testing cases passed.
- [x] Commit only the six reviewed files as `e4a01131`; push and verify remote SHA.

## Task 2: Prepare fork release metadata

Files: `release.json`, `Support/Info.plist`, `.github/workflows/release.yml`, `release-notes/1.9.3/*.md`, affected workflow contract tests.

- [x] Pin version 1.9.3/build 50 and fork update/feed configuration.
- [x] Generate a new fork update signing key without displaying or persisting the private value in workspace files; verify a sample signature and store the private key only in GitHub encrypted secrets.
- [x] Add all 12 shipped release-note languages for the personal changes.
- [x] Keep the existing workflow unchanged; set RELEASE_REPO/RELEASE_BRANCH variables to the fork/main instead of changing pipeline defaults.
- [x] Validate release-note coverage (12/12 languages).
- [x] Validate offline pipeline contracts in the full profile.

## Task 3: Resolve release findings and verify

- [x] Diagnose exact icon raster failures using independent evidence; preserve measured-ink alignment and scene parity.
- [x] Run focused checks while iterating, then one `verify-local.sh full` on the final integrated tree.
- [x] Obtain read-only code/Swift/security review of any new implementation/configuration changes.
- [ ] Commit release preparation separately and push the release branch.

## Task 4: Integrate and publish

- [ ] Fetch/compare the latest fork `main`, use a PR for the accumulated multi-subsystem changes, and integrate after local checks.
- [x] Configure fork release variables and a `distribution` environment limited to `main`, with the repository owner as required reviewer.
- [ ] Freeze the merged candidate SHA and dispatch `release.yml` from `main` with version 1.9.3/build 50/publish=true.
- [ ] Present the concrete waiting deployment for human approval; explain the project rule requiring that approval.
- [ ] Follow all jobs to completion; verify the published tag, manifest, DMG digest and appcast URLs against that same artifact.
- [ ] Keep the user's daily installation on the source-built Personal development app.
