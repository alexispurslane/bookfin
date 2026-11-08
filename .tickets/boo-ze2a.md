---
id: boo-ze2a
status: closed
deps: []
links: []
created: 2026-11-07T15:10:14Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Let password managers fill sign-in and show a round launcher icon


## Notes

**2026-11-07T15:10:18Z**

Sign-in fields now carry url/username/password autofill hints inside one AutofillGroup. finishAutofillContext saves only after a successful sign-in. Launcher icon is an adaptive icon (drawable-anydpi-v26) so the launcher masks it round; the pre-26 fallback is a circle. Widget test added. Built debug APK; phone install pending reconnect.

**2026-11-08T02:52:43Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
