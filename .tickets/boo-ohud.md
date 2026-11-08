---
id: boo-ohud
status: in_progress
deps: [t2-u76g]
links: [t2-y0ce]
created: 2026-11-02T22:32:26Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Complete Android EPUB resource denial and accessibility acceptance

Finish remaining boo-9wgg and t3-9r9u runtime gates after saved-page correction: actual native resource/navigation/permission denial, representative local assets and SVG fallback, applied fonts, TalkBack and focus, large text and offline controls. User requested completion on November 2. Theme lifetime remains t8-j809.

## Acceptance Criteria

Named normal Android source/APK; observed bounded adversarial publication and request-attempt evidence; representative asset and font results; actual TalkBack reading/focus/control behavior and OS large text. Record unsupported host capabilities and defects honestly. Retain sanitized screenshots and cleanup; parent integration and closure.

## Bounded Android evidence (2026-11-02)

Normal Nix Android source `17c9e6bf175a5586566441183b8e8ed19534c1b6`, APK SHA-256 `8e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b`. Final installed readback matches. Production runtime and sandbox are unchanged in this lane. Earlier source `c279fd6` observations remain explicitly separate.

Actual current WebView requests serve admitted PNG with 200 and refuse missing/query/POST resources with 403. Diagnostic navigation is attempted and canceled. Owned sink endpoints have native Chrome HTTP-200 positive controls. Remote fetch is stopped by CSP; the direct network probe is stopped by native cleartext policy. Permission attempts fail through Permissions-Policy, not independently observed native permission callbacks. No arbitrary remote HTTPS interception claim.

PNG/JPEG, exact passive SVG JPEG-wrapper fallback, active SVG unsupported marker, actual custom publisher-font glyphs, Android selection handles/menu, OS scale 1.75 reflow/paging, offline process restart, and offline local images/fonts pass on the named normal APK. Actual TalkBack remains externally blocked: installed and enabled service stays unbound under host UiAutomation. Follow-up `t2-u76g`; no app accessibility failure inferred. No broad reader acceptance or ticket closure.

See `docs/evidence/reader/android-remaining.md`, its per-case artifacts, failure audit, and cleanup. Settings restored, own download removed, signed out, servers/routes/Gradle stopped, bound session closed, device released without shutdown. Parent owns integration and remaining gate decisions.

Post-release readback still found signed-out Bookfin PID11695 despite successful session close. One named-app close attempt through the same now-removed executable failed No such file or directory. No binding reset or adb UI fallback. Host follow-up `t2-y0ce`; app-process termination remains an explicit cleanup limit.

## Notes

**2026-11-08T19:23:53Z**

Note from epic boo-b2ey (2026-11-08). The WebView reader goes away. The resource, navigation and permission denial checks here test the WebView, and they become obsolete when tc-rap6 merges. TalkBack, publisher fonts, SVG fallback, large text and offline reading need a new check on the native reader: tc-fz4n (TalkBack, large text), tc-nh0b (publisher fonts), tc-cl77 (SVG fallback) and tc-1yif (device check, offline). Do not spend more work on WebView evidence here.
