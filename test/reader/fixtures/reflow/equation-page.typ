// The born-digital reflow fixture of docs/plans/pdf-word-image-reflow.md.
// test/reader/fixtures/reflow/README.md says how to make equation-page.pdf.
#set document(title: "Falling bodies", date: none)
#set page(paper: "a5", margin: (x: 1.8cm, y: 2cm))
#set text(font: "Libertinus Serif", size: 11pt, lang: "en")
#set par(first-line-indent: 1.2em, justify: false)

#align(center, text(size: 15pt, weight: "bold")[Falling Bodies])

A stone that falls from rest gains speed at a steady rate. After a time
$t$ it moves at $v = g t$, and it has fallen a distance of $g t^2 slash 2$.
The square of the time is the reason that a fall of twice the height
takes less than twice as long.

If the stone starts with a speed $u$, its speed after a fall through a
height $h$ follows from the same rule:

$ v^2 = u^2 + 2 g h $

The table gives three falls that the rule predicts.

#align(center, table(
  columns: 3,
  [Body], [Height], [Time],
  [Stone], [5 m], [1.0 s],
  [Apple], [20 m], [2.0 s],
))

#par(justify: true)[Measurements of extraordinarily unhurried descents
through viscous atmospheres nevertheless demonstrate approximately
identical accelerations, notwithstanding considerable differences between
individual specimens.]

