// The trimmed margins fixture of docs/plans/pdf-word-image-reflow.md: a
// short book with running headers, folios at the outer bottom corners,
// chapter starts without a header, footnotes, a figure near the bottom of a
// page and a table wider than the text.
// test/reader/fixtures/reflow/README.md says how to make margins-book.pdf.
#set document(title: "A Short Book of Motion", date: none)
#set text(font: "Libertinus Serif", size: 10.5pt, lang: "en")
#set par(justify: true, first-line-indent: 1.2em)

// Even pages carry the book's title, odd pages the chapter's title. A page
// that starts a chapter has no header. The folio sits in the outer bottom
// corner. The title page has neither, and the folio of the page after it
// is 1, so each folio is its source page number minus one.
#set page(
  paper: "a5",
  margin: (inside: 20mm, outside: 14mm, top: 22mm, bottom: 22mm),
  header: context {
    let number = here().page()
    let starts = query(heading.where(level: 1)).filter(it => (
      it.location().page() == number
    ))
    if number > 1 and starts.len() == 0 {
      set text(size: 9pt, style: "italic")
      if calc.odd(number) {
        align(center, query(heading.where(level: 1).before(here())).last().body)
      } else {
        align(center)[A Short Book of Motion]
      }
    }
  },
  footer: context {
    let number = here().page()
    if number > 1 {
      set text(size: 9pt)
      align(if calc.odd(number) { right } else { left }, counter(page).display())
    }
  },
)
#show heading.where(level: 1): it => align(
  center,
  block(below: 1.4em, text(size: 17pt, weight: "bold", it.body)),
)

#let pool = (
  "A stone that falls from rest gains speed at a steady rate, and the rate does not depend on the weight of the stone.",
  "Galileo rolled bronze balls down a long groove in a wooden beam, so that the motion was slow enough to time with a water clock.",
  "The distances that a ball covers in equal times grow as the odd numbers: one, three, five and seven.",
  "So the whole distance from rest grows as the square of the time, and a fall of four times the height takes twice as long.",
  "Air pushes against a falling body, and a feather meets more air for its weight than a coin does.",
  "In a tube without air, the feather and the coin reach the bottom together.",
  "A body thrown sideways keeps its sideways speed while it falls, and the two motions together draw a curve.",
  "The curve is a parabola, which the old gunners knew from practice before anyone could explain it.",
  "A weight on a string swings back and forth, and each swing takes nearly the same time.",
  "The time of a swing depends on the length of the string, and hardly at all on the width of the swing.",
  "A string four times as long swings half as fast, which is the rule of the falling stone in another form.",
  "Clockmakers used this rule to make clocks that lost less than a minute in a day.",
  "A pendulum on a long wire, left to swing for a day, slowly turns the plane of its swing.",
  "The turn shows that the floor under it moves, carried by the spinning earth.",
  "Near the poles the plane turns once a day, and at the equator it does not turn at all.",
  "Measurements made with great care in many cities agree with this rule to a small fraction of a degree.",
  "The same pull that brings the stone down keeps the moon on its path around the earth.",
  "The moon falls toward the earth all the time, but it moves sideways fast enough to keep missing it.",
  "Every careful experiment begins with a question that the experimenter can answer with a ruler and a clock.",
  "The answers are numbers, and the numbers either fit the rule or show where the rule must change.",
)

// [count] sentences of the pool from [start], in paragraphs of up to
// seven sentences.
#let body(start, count: 18) = {
  let picked = range(count).map(i => pool.at(calc.rem(start + i, pool.len())))
  for first in range(0, count, step: 7) {
    par(picked.slice(first, calc.min(first + 7, count)).join(" "))
  }
}

// Page 1: the title page.
#v(30%)
#align(center, text(size: 22pt, weight: "bold")[A Short Book of Motion])
#v(1em)
#align(center, text(size: 12pt)[Written for the Bookfin tests])
#counter(page).update(0)
#pagebreak()

// Page 2: the start of the first chapter.
= Falling Bodies
#body(0)
#pagebreak()

// Page 3.
#body(3)
#pagebreak()

// Page 4: footnotes.
#par[The rule of the odd numbers#footnote[Galileo states it in the third day of his _Two New Sciences_, published in 1638.] holds for every body that falls freely, whatever its size.]
#body(7, count: 12)
#par[A pendulum clock#footnote[Christiaan Huygens built the first one in 1656.] keeps time by the same law.]
#pagebreak()

// Page 5.
#body(11)
#pagebreak()

// Page 6: a figure near the bottom of the page.
#body(14, count: 11)
#v(1fr)
#figure(
  box(width: 6cm, height: 2.6cm, {
    place(line(start: (0.4cm, 0.1cm), end: (0.4cm, 2.5cm), stroke: 0.8pt))
    for step in range(5) {
      place(
        dx: 1.4cm + step * 0.9cm,
        dy: (0.15 + step * step * 0.13) * 1cm,
        circle(radius: 0.16cm, fill: black),
      )
    }
  }),
  caption: [A ball drawn at equal times as it falls.],
)
#pagebreak()

// Page 7.
#body(17)
#pagebreak()

// Page 8: the start of the second chapter.
= The Pendulum
#body(8)
#pagebreak()

// Page 9.
#body(12)
#pagebreak()

// Page 10: a table wider than the text.
#body(15, count: 11)
// The cells of the two columns meet at the middle rule, so that each row
// of the text layer reads as one phrase.
#pad(x: -10mm, table(
  columns: (1fr, 1fr),
  align: (right, left),
  [The length of the string in metres], [The time of one whole swing in seconds],
  [A quarter of a metre, or 0.25 m], [One second, and sixty swings in a minute],
  [Nearly one metre, or 0.99 m], [Two seconds, and thirty swings in a minute],
  [About two metres, or 2.24 m], [Three seconds, and twenty swings in a minute],
))
#par[The longer the string, the fewer the swings in an hour, and the smaller the share of each error.]
#pagebreak()

// Page 11.
#body(2)
#pagebreak()

// Page 12.
#body(6)
#pagebreak()

// Page 13.
#body(10)
