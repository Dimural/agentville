# 0003: Minimum macOS 14 Sonoma
Status: Proposed
Date: 2026-10-01

## Context
The minimum version decides which window, SwiftUI and SpriteKit APIs we can use. The brief left it open.

## Decision
macOS 14 Sonoma as the deployment target.

## Consequences
- Modern SwiftUI (`MenuBarExtra`, `Settings`, `@Observable`) is available for the settings and welcome windows.
- Covers the large majority of developer Macs in 2026 while staying two years behind current.
- Verify on macOS 14 that polling `NSEvent.modifierFlags` and `mouseLocation` triggers no permission prompt.
