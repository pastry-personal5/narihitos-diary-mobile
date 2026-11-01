# P1-M3: Scaffolding approach

Status: Done

Keep the initial target small while making the build setup reproducible and leaving feature boundaries available for later milestones.

## Targets and boundaries

- `NarihitosDiary`: SwiftUI composition root, placeholder view, and a Foundation-only launch version policy.
- `NarihitosDiaryTests`: direct tests of the launch version policy.
- `project.yml`: XcodeGen source of truth; no generated project needs hand editing.

The initial app has no storage, microphone, network, or model adapter. Later feature code follows the inward dependencies in the [software architecture](../architecture.md).

## Sequence and validation

1. Add the version policy and app target sources.
2. Add the XcodeGen spec and test target, then generate the project.
3. Add a quiet check script: command logs go to files; the terminal shows each check's result and a short error tail on failure.
4. Run the formatting and lint gate and build/test gate. Keep blocked items unchecked if CoreSimulator remains unavailable.

Xcode's deployment target uses 27.0; the app enforces the owner-approved 27.0.1 patch minimum at launch. This resolves the project-setting question without changing the product minimum.
