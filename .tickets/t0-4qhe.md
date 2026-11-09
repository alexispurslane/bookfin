---
id: t0-4qhe
status: open
deps: [t0-u3nc, t0-bv9p, t0-f9iu, t0-bomb]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Read the open book aloud: queue, player, media session, follow and saved place

ReadAloud data source created by ReaderSession for an open EPUB or MOBI book. Start at the first sentence of the shown page, reuse saved segments, keep 2 to 10 minutes ready ahead, play segments with just_audio as a growing playlist with time-stretch speed, claim the media session from Playback and give it back, follow the speech with page turns, and give the session the spoken place at pause, stop, seek, chapter change, background and close. Never lose a place (AGENTS.md engine rule 3). Reader dock controls and the voice sheet are glass. See 'Design' in docs/research/on-device-tts.md.

