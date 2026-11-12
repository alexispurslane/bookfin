---
id: t1-m4cp
status: closed
deps: []
links: []
created: 2026-11-12T14:00:51Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Rerun the EPUB engine benchmark against KOReader and WebView on current main

Rerun the drawn-page benchmark of sym-drawn4 (docs/marketing/epub-renderer/README.md) with Bookfin's shell rebuilt from current main, after boo-yjq6, boo-sy2d, boo-iv7q and boo-3huo. Same books, actions, endpoints, frame-wait rule, host-GPU emulator, load guard and equal-book-weight means. Bookfin adds honest rows: fresh open prepared at download and without preparation, background preparation time, cached reopen to the kept page and to the true page. KOReader and WebView rows stay defined as before.


## Notes

**2026-11-12T14:13:10Z**

Harness at 40d9c9c5: Bookfin shell rebuilt from main 255da777; WebView and KOReader release and test APKs reused byte for byte from sym-drawn4 (t3-2ccd2d93 build outputs, hashes in evidence/rerun-20261112/install.txt). Own AVD bookfin-bench-rerun (copy of bookfin-bench-gpu config, same system image) on emulator-5562, pixel_7 cutout overlay on. Old references-gpu.json still match Bookfin pixels in all check jobs. Run rerun1 started: 108 standard jobs plus 36 Bookfin prepared-at-download jobs.

**2026-11-12T15:33:35Z**

rerun1 complete: 144 jobs accepted (18 set aside after 22 busy attempts, one stop at job 89, resumed with --start 88), 1,440 accepted samples, none excluded, load before accepted jobs 5.0 to 7.99, highest reading 7.99. Equal-book means Bookfin: fresh open no preparation 195.5 (was 370.3), prepared at download 65.4, preparation at download 150.0 (background), cached reopen kept page 9.6 and true page 31.2 (was 46.9), page turn 8.2, chapter turn 4.2, size change 35.6. WebView 355.3/289.0/52.5/47.8/64.8; KOReader 127.9/17.4/2.6/3.1/70.0. Kept page shown and depicted the true page in 108 of 108 reopens. README section 'Rerun on current main: November 12, 2026'. index.html unchanged for the orchestrator. Emulator bookfin-bench-rerun stopped.

**2026-11-12T15:34:35Z**

Merged to main at 5a0e919f. Orchestrator: 102 harness tests pass. Homepage table not changed yet; waits for the user.
