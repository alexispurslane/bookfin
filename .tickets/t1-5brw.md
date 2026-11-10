---
id: t1-5brw
status: closed
deps: []
links: []
created: 2026-11-10T15:22:46Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Leave scan-edge regions out of the word view

Found in tb-z9h5. PageAnalysis.isScanEdge(region, geometry) finds a region that touches a page edge, runs along more than half of it and is thinner than the body line height, such as the dark bottom edge of the Raven scan (a picture region 1600 by 14 pixels). The content box leaves such regions out. The word view (tb-0mex column layout, tb-m8xo) still treats them as picture regions, so the Raven page would end with a dark band. Skip scan-edge regions where the column layout places regions.


## Notes

**2026-11-10T16:46:30Z**

Built (2026-11-10). PageAnalysis.isContentRegion(region, geometry) (no running region, no scan edge) is the one rule that contentBox and the column (_Source.shows) use. The Raven word view ends with its folio. Test: column_layout_test 'the dark bottom edge of the Raven scan does not show'.
