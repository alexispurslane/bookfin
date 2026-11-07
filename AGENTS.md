# Bookfin implementation rules

## Approved product

Read `docs/plans/bookfin.md` and your ticket before implementation. The user approved `docs/mockups/bookfin.html`, including its revised cream/sepia aesthetics. Preserve its feature structure and information layout nearly exactly. Android is the primary target. Use Flutter, hot reload, and the shared T3 Device panel. Prove Jellyfin-only personal-record sync first; a small Jellyfin plugin is an accepted fallback.

## Agents and orchestration

The user requires every subagent to use Codex `gpt-6.1-sol` with `reasoningEffort: high`. This applies to builders, researchers, reviewers, fixers, and test agents. Never substitute another model or effort. A child performs its own task and starts no children unless its brief explicitly authorizes them. Follow the host's delegation and workflow rules.

Track work with `tk`. Read `tk ready` and the dependency tree. Keep ticket changes with the work they describe. Start a ticket when its work begins. Only the orchestrator closes a ticket after integration. Record newly found work as tickets. The epic is `boo-fs0n`; its design is `docs/plans/bookfin.md`.

## Design and testing

Read `/Users/alexispurslane/.agents/skills/software-design/SKILL.md` before design or implementation. Prefer one coherent model for existing and new behavior, one owner per state or decision, and simple interfaces over hidden complexity. Do not add abstractions for hypothetical callers. Follow the user's module-oriented, composition-based style.

At a genuine product design fork, report two designs and their costs to the orchestrator. Do not settle a user-visible tradeoff that the plan and reasonable defaults do not resolve. Do not block routine wiring or settled implementation decisions on approval.

Read `/Users/alexispurslane/.agents/skills/test-driven-development/SKILL.md` before behavior implementation. Write domain-language behavior tests, prove meaningful failure, then implement and refactor. An initial batch can define core behavior; work through it one test at a time. Do not treat syntax or missing-reference failures as meaningful red tests. Avoid tests that merely mirror constants or implementation.

After user acceptance, the orchestrator coordinates coverage, mutation testing, invariant checks, and survivor triage under `/Users/alexispurslane/.agents/skills/test-hardening/SKILL.md`. Do not run competing hardening jobs. Reviewers read `/Users/alexispurslane/.agents/skills/software-design/references/reviewer-brief.md` and assess correctness, ticket fulfillment, and design separately. Reviewers do not edit, build, or test.

Use contracts only for core data structures, business logic, and orchestration that maintains related state. Public arguments use always-on guards. Internal preconditions/postconditions compile out in release. Document invariants and expose one on-demand invariant checker usable in every build. Never recover from contract failures. Tests, not contracts, check behavior.

## UI architecture rules

These are hard rules for all new and changed Flutter code. When you touch code that breaks them, fix the code you touch or record a ticket.

1. Data down, actions up.
   - Only controllers cause side effects. Controllers are the app-wide data sources (catalog, playback, downloads, reader, appearance, sync) and the tab or page widgets that act as controllers for their screen. Side effects include network and storage access, playback and download commands, record changes, navigation, and confirmation dialogs before an action.
   - Every other widget reports what happened through a callback and causes no side effect. As an event bubbles up, it gains data and becomes more abstract. Example: a trash icon calls `onRemove(edition)`, and the tab confirms and then tells Downloads to remove the edition.
   - Data that outlives one widget lives in a data source or a tab controller, never in a leaf widget's State. This includes fetched data, futures, caches, and anything that survives navigation or an app restart. Widgets receive that data through constructor parameters or through an `InheritedWidget` scope. A widget may keep only ephemeral UI state, such as an expanded row, a text controller, an animation, or a drag preview.
2. One component for each kind of thing. When two widgets do relevantly similar things, one widget does both. Customize it through parameters, `child`, `children` or builder slots, and callbacks. Factor when the second copy appears, not for hypothetical callers.
3. Depend on the minimum, and subscribe at the lowest level. Each widget depends on the least data that it needs. A controller passes data sources, or narrow listenables, down; it does not pass changing values that would force it to rebuild. The lowest widget that shows a value subscribes to it, for example with `ValueListenableBuilder`, a narrow `ListenableBuilder`, or an `InheritedModel` aspect. A data source exposes narrow change signals instead of one notification for everything. Example: the app shell depends only on the selected tab and on whether the user is signed in.

## Environment and devices

Keep the project under `~/Development/bookfin`. Provide a pinned Nix flake with `devShells.<system>.default`. Run build and test commands through `nix develop`. Put required environment variables in the dev shell, never the user's shell profile. Do not install toolchains globally. Pin sources and hashes for native dependencies absent from nixpkgs. Stage new `.nix` files before a Git flake uses them.

Use T3 `device_list`, then `device_open` with the returned host/device identifiers. Use the returned device-bound `agent-device` command for every app launch, input, settings action, screenshot, and recording. Use `device_screenshot` to inspect the screen. Never substitute adb/simctl/ssh for those actions. Build, install, logs, and test runners can use their normal tools. Read the active host rules for failures and unavailable platforms.

Use T3 browser tools for requested browser work, starting with `preview_status`. Show generated visuals with `html_preview` then `html_render`. Keep visuals self-contained. Do not expose a public unauthenticated dev server. Request secrets with T3's private secret input, never in chat or logs.

At planning time T3's device host was installed but Android discovery failed because command-line tools were missing at `/Users/alexispurslane/Library/Android/sdk`. Resolve discovery using the project-managed SDK without overwriting another SDK. Do not claim phone access or hot reload until observed.

## Communication and ownership

Begin conversational replies with a suitable kaomoji. Use plain English and no bold. Use lists for three or more parallel items and tables when items share comparison aspects. Define technical terms. When explaining actual code logic, show the exact code and define its variables/functions. For design questions, explain causes and state ownership without code unless requested. Use diagrams for structures when helpful.

Do not overwrite unrelated work or reset a shared checkout. Stage files by name. Commit ticket updates with their changes. Report exact verification, remaining limitations, commit SHA, and any user decision needed. Do not claim that a mockup implements real Android behavior. The orchestrator handles final integration and closure.
