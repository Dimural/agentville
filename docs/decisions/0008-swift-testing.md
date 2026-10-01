# 0008: Swift Testing for all tests
Status: Accepted
Date: 2026-10-01

## Context
Swift Testing (`import Testing`, `@Test`, `#expect`) is the modern framework. On machines with only the Command Line Tools, neither XCTest nor Testing is on the default search path, but Testing.framework ships with the CLT.

## Decision
All tests use Swift Testing. `scripts/swift.sh` adds `-F`/`-rpath` flags for the CLT's `Testing.framework` when full Xcode isn't usable.

## Consequences
Tests run identically with Xcode or the CLT alone. No XCTest dependency.
