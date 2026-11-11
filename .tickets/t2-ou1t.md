---
id: t2-ou1t
status: in_progress
deps: []
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Find heard words in an ebook's words

Port the prototype's proven search (tool/research/cross_edition/speech_probe): normalized words (numbers as words), the book words of a downloaded EPUB or MOBI with visible characters as BookMap counts them, body text only, the rarity-weighted diagonal vote, the word alignment, the confident-match rule and the growing radii. A worker isolate keeps the book words and runs the searches.


## Notes

**2026-11-11T23:07:05Z**

Built in lib/speech: words.dart (normalizeWords, Heard.fromTokens), book_words.dart (BookWords, bookWordsOf: words of an admitted EPUB with visible characters as countSection counts them, inline markup kept inside a word, back matter left out by contents title), search.dart (the prototype's vote, alignment, confident rule, nearRadii and wholeBookRadii), book_search.dart (BookSearch: one worker isolate keeps the two latest books and runs closures on their words) over worker.dart (KeptWorker: a long-lived worker with an idle stop, shared with the speech runtime). Tests: test/speech/{words,book_words,search,book_search}_test.dart. The reader of downloaded files joins in t2-v4eq.
