---
id: t5-vbno
status: closed
deps: []
links: []
created: 2026-11-08T20:12:42Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Sign release APKs so that a release build installs on a device

flutter build apk --release gives an unsigned APK (apksigner: Missing META-INF/MANIFEST.MF), because android/app/build.gradle.kts defines no release signingConfig. The install fails. For the boo-lxzv check, a copy was signed by hand with the local debug key. Decide on the release key, and relate this to the flake APK package (boo-77sj).


## Notes

**2026-11-14T14:47:05Z**

Release key decided: a dedicated key in ~/.config/bookfin/release.jks and GitHub secrets. Gradle signs release builds through BOOKFIN_RELEASE_SIGNING (boo-i5r0).
