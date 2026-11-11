// The PDF outline fixture of docs/plans/cross-edition-places.md: a short
// book whose bookmarks nest chapters inside parts, with a chapter that
// starts partway down a page and a page that holds only a picture.
// test/reader/fixtures/outline/README.md says how to make parts-book.pdf.
#set document(title: "A Short Book of Weather", date: none)
#set text(font: "Libertinus Serif", size: 10.5pt, lang: "en")
#set par(justify: true, first-line-indent: 1.2em)
#set page(paper: "a5", margin: (x: 16mm, y: 20mm))
#show heading.where(level: 1): it => align(
  center,
  block(above: 2em, below: 1.2em, text(size: 17pt, weight: "bold", it.body)),
)
#show heading.where(level: 2): it => block(
  above: 1.6em,
  below: 1em,
  text(size: 13pt, weight: "bold", it.body),
)

#let pool = (
  "Warm air rises from the ground on a sunny day, and it cools as it climbs.",
  "Cool air holds less water than warm air, so the water in it gathers into small drops.",
  "A cloud is a crowd of these drops, each far too small to fall on its own.",
  "The drops bump into each other and join, and the larger drops grow faster than the small ones.",
  "When a drop grows heavy enough, it falls, and on its way down it gathers more drops.",
  "Most rain in cool countries starts as snow high in the cloud and melts as it falls.",
  "Air moves from places where it presses hard to places where it presses less.",
  "The spinning earth turns the moving air aside, to the right in the north and to the left in the south.",
  "So the wind blows around a low instead of straight into it.",
  "Sailors learned to read the turning wind long before anyone could explain it.",
  "Snow forms when the drops freeze in the cloud and grow by taking water from the air around them.",
  "Each crystal has six arms, because of the way that frozen water builds itself.",
  "No two crystals meet the same air on their way down, so no two grow alike.",
  "A careful observer writes down the sky, the wind and the temperature at the same hours every day.",
  "Years of such notes show the patterns of a place, and the patterns become its climate.",
)

// [count] sentences of the pool from [start], in paragraphs of up to six
// sentences.
#let body(start, count: 16) = {
  let picked = range(count).map(i => pool.at(calc.rem(start + i, pool.len())))
  for first in range(0, count, step: 6) {
    par(picked.slice(first, calc.min(first + 6, count)).join(" "))
  }
}

// Page 1: the title page.
#v(30%)
#align(center, text(size: 22pt, weight: "bold")[A Short Book of Weather])
#v(1em)
#align(center, text(size: 12pt)[Written for the Bookfin tests])
#pagebreak()

// Page 2: the first part and its first chapter.
= Part One: Water
== Chapter 1: Clouds
#body(0, count: 12)
#pagebreak()

// Page 3: the end of chapter 1, then chapter 2 starts partway down.
#body(12, count: 6)
== Chapter 2: Rain
#body(3, count: 8)
#pagebreak()

// Page 4.
#body(5)
#pagebreak()

// Page 5: a picture without words, and so without a text layer.
#align(center + horizon, box(width: 9cm, height: 9cm, {
  place(rect(width: 9cm, height: 9cm, stroke: 0.8pt))
  for step in range(6) {
    place(
      dx: 1cm + step * 1.3cm,
      dy: (1 + calc.rem(step * 7, 5) * 1.2) * 1cm,
      circle(radius: 0.5cm, fill: black),
    )
  }
}))
#pagebreak()

// Page 6: the second part and its first chapter.
= Part Two: Air
== Chapter 3: Wind
#body(6, count: 12)
#pagebreak()

// Page 7.
#body(9)
#pagebreak()

// Page 8: the last chapter.
== Chapter 4: Snow
#body(10, count: 14)
#pagebreak()

// Page 9.
#body(13)
