# AGENTS.md

## Project objective

Reimplement the existing Next.js application in `web/` as a native SwiftUI application in `ios/`.

The Next.js application is the behavioral and visual reference. The SwiftUI application is the implementation target.

## Source-of-truth rules

- Treat everything under `web/` as read-only unless explicitly asked to change it.
- Make implementation changes only under `ios/` unless explicitly instructed otherwise.
- Use the Next.js application to understand:
  - Product behavior
  - Business rules
  - Validation
  - Data transformations
  - Navigation
  - Loading, empty, success, and error states
  - Visual hierarchy and design intent
- Do not mechanically translate React components into SwiftUI.
- Reimplement behavior using idiomatic Swift, SwiftUI, and Apple platform conventions.
- When the web implementation is ambiguous, report the ambiguity instead of inventing behavior.

## Architecture

- Keep SwiftUI views focused on presentation.
- Put business rules and data transformations in independently testable Swift types.
- Put networking behind protocols so implementations can be replaced in tests.
- Use structured concurrency with `async`/`await`.
- Use the Observation framework when supported by the configured deployment target.
- Prefer value types and explicit application state.
- Do not add third-party dependencies without approval.

## Web-to-SwiftUI mapping

Before implementing a feature:

1. Identify the relevant Next.js routes, components, hooks, schemas, services, and tests.
2. Document the observable behavior and edge cases.
3. Identify browser-only and server-only behavior that cannot run directly on iOS.
4. Propose the corresponding SwiftUI views, models, services, and tests.
5. Implement one complete vertical slice.
6. Build and test it before proceeding to the next feature.

## Business-logic parity

- Preserve calculations, validation, state transitions, ordering, filtering, and error behavior.
- Translate pure TypeScript business logic into testable Swift.
- Add XCTest cases for normal, boundary, invalid, and failure inputs.
- When possible, use shared JSON fixtures from `fixtures/` so the TypeScript and Swift tests evaluate identical inputs and expected outputs.
- Do not move server-only logic or secrets into the iOS application.
- Next.js server actions, route handlers, database operations, and secret-bearing integrations must remain behind an authenticated API.

## Design translation

- Match the web application's information hierarchy, content, branding, spacing relationships, and interaction intent.
- Use native SwiftUI navigation, controls, sheets, alerts, accessibility, and platform behavior.
- Do not force a pixel-for-pixel web layout when it conflicts with iPhone or iPad conventions.
- Support Dynamic Type, VoiceOver, safe areas, light/dark appearance, and appropriate device sizes.
- Use assets supplied by the project. Do not download substitute assets without approval.

## Safety

- Never copy `.env` values, API secrets, database credentials, private keys, or server credentials into the iOS application.
- Do not change bundle identifiers, signing, entitlements, capabilities, or deployment targets without approval.
- Do not modify generated Xcode project files unnecessarily.

## Verification

After each feature:

- Build the relevant Xcode scheme.
- Run relevant unit and UI tests.
- Compare the implemented behavior with the corresponding Next.js behavior.
- Report which web files were used as references.
- Report any behavior that was intentionally adapted for native iOS.
- Report anything that could not be verified.