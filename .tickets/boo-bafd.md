---
id: boo-bafd
status: open
deps: []
links: []
created: 2026-11-08T02:56:28Z
type: bug
priority: 0
assignee: Alexis Purslane
parent: boo-fs0n
---
# Launch shows the sign-in form for about 17 seconds while the saved library loads

Found on the Pixel 8 on Nov 7 with build 1abdb6b (debug APK) and the user's real library of about 1,500 books. After a cold start, the app shows the sign-in form ('Your library starts here.') with a disabled Sign in button and a Cancel button for about 17 seconds, then the library appears. Cancel there calls catalog.signOut(), so a tap signs the user out. Cause seen in lib/catalog/controller.dart _restore: it sets _session from the saved credentials, then awaits _readSaved (read and build of the saved library), and notifies only in finally. Until then the shell sees no session and shows _SignInForm, which shows Cancel because catalog.busy is true. This breaks engine rule 2: the saved library must be the first useful frame. Find where the 17 seconds go (secure storage read, catalog store read, the hop, the build, covers) by measurement on emulator-5556, which is signed in to the same real server. Then: never show the sign-in form while a restore runs with saved credentials, publish the signed-in state as soon as the credentials are read, show the saved library as soon as it is built, and make the restore itself fast. Measure the time to the first library frame before and after, in a debug and a profile or release build.

