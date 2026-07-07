# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Generic project guidance (build/test/run, architecture, release, conventions):
@AGENTS.md

## Claude-specific notes

- **Vendored dependency**: `swift build`/`swift test` need a sibling checkout at
  `../thermal-fan-guard-vendor` (from https://github.com/agoodkind/macos-smc-fan).
  If it is missing, clone it there before building — the failure is a package
  resolution error, not a code problem.
- The daemon needs root; put unit-testable logic in `ThermalFanGuardCore` (the only
  test target) so it can be exercised without root or SMC hardware.
- Cursor rule `.cursor/rules/release-versioning.mdc` mirrors the tag-as-version
  release policy documented in `AGENTS.md`; keep both in sync when it changes.
