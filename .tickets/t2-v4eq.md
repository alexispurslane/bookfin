---
id: t2-v4eq
status: in_progress
deps: [t2-ou1t, t2-xkzt]
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Land places of the other edition by speech in Crossings

The speech stage of Crossings (docs/plans/cross-edition-places.md, S2). A listening place lands in the ebook by its own heard window, by two heard anchors at most 10 minutes apart, or by a window heard at the tap. A reading place lands in the audiobook from the anchors' or the chapters' estimate through the prototype's reading-place loop (version 4). MatchedBy.speech, refusal instead of guessing, fallback to matched chapters or to the screen switch. Speech starts when an entry of the other medium opens.


## Notes

**2026-11-11T23:58:26Z**

Built the speech stage. lib/speech/place.dart: landHeard, densePairs, ReadingSearch (prototype loop v4 as a round-by-round state machine: the caller hears and searches, fold() decides), findAnchors (now with the anchor's word), charactersBetween/millisecondsBetween (two anchors at most 10 min apart that read at 270-540 ms a word). lib/crossings/speech_places.dart: SpeechPlaces owns the BookSearch worker and an anchor map per pair that grows by the windows not yet searched; charactersAt = covering window, else two anchors, else hear now; millisecondsAt = estimate from anchors, else chapters, else share, then ReadingSearch with kept or urgent windows. Crossings: MatchedBy.speech, Landing.matchedBy field, new Settled type (landing() always settles), Refining(estimate) from landingNow while a place's speech work runs, prepare() grows the anchor map, refused speech results retry when downloads change, speech results checked in checkInvariants. audioPlaceAt moved to audio_outline.dart. bookWordsReader (reader/platform_io.dart) reads EPUB and MOBI words in the worker; PDF gives null (t2-9csd). Timeline tiles name Refining's estimate with 'about'. Tests: test/speech/place_test.dart (12), test/crossings/speech_landings_test.dart (8).
