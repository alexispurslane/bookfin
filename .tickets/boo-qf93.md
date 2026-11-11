---
id: boo-qf93
status: open
deps: []
links: []
created: 2026-11-11T00:02:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Restore Bookfin Pages publication after homepage updates

Published xenolandscapes.tngl.io/bookfin still serves exactly the index.html bytes from1fd94309 despite tangled/main atb8be011. Both normal and cache-bypassing requests return old HTML SHA256 b0f47650914e5524395cf77993cb2d258099d6e0b306120d95c825bcd4cf4785; new Nihil image returns404. Server advertises max-age60. Investigate Pages deployment source/settings and restore current homepage publication; do not assume browser cache.


## Notes

**2026-11-11T00:03:47Z**

Browser verification: live HTML matches1fd94309 exactly (24430 bytes), with max-age60; no-store request plus unique query returns same old bytes, and current NU asset404. Remote main is b8be011. Official docs https://tangled.org/docs/sites/ say Settings→Sites selects branch and deploy directory, with redeploy on pushes or settings changes. No CI pipelines have run; Sites is configured separately. Repository settings redirect to Tangled login in the shared browser, so awaiting user sign-in before inspecting configuration. Do not claim a definite deployment failure cause beyond the observed stale publication.

**2026-11-11T00:07:15Z**

User explicitly deferred deployment investigation for now. Do not request Tangled sign-in or continue Sites work until resumed.
