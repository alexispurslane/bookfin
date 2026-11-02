# EPUB navigator integration evidence

Research date: November 2, 2026. Base: `261d50eb48dbe78288d44419d692e27268430a78`.
Tickets: `t3-9r9u` and upcoming `boo-9wgg`.
This work changes no production application dependency or reader screen.
No package is approved by this report.

## Recommendation and decision

Use a bounded fork of `flutter_epub_viewer` 2.2.1 as the first production integration candidate.
Use the separately pinned epub.js 0.3.93 distribution instead of assuming the wrapper's different bundled engine has that provenance.
Keep the approved Flutter reader controls around its document viewport.
This is an XHTML/CSS document renderer with a navigator, not extracted text placed in a Flutter text widget.
XHTML means the chapter markup inside EPUB.
Removing standalone HTML and Markdown books does not remove XHTML from EPUB.

The candidate already supplies contents, document navigation, reflow settings, search results, text selection, and reading-location events.
Host probes run those document operations on nine EPUB editions.
The clean upstream engine also passes the same probes, including bounded research fixes for search.
It does not require EPUBX, so it avoids the existing EPUBX/image/archive dependency fork.
pdfrx 2.11.0 and this candidate resolve together without overrides in a separate dependency-solver probe.
That is a solver result, not another native runtime proof.

Do not integrate the unmodified package as a safe reader.
Its resource interceptor delegates other hosts to the WebView, its navigation callback permits navigation, and its permission callback grants requests.
It serves active SVG unchanged.
Two executable security requirements fail against the unmodified package.
The production fork must own resource admission and passive-content handling before any untrusted edition is opened.
Passive content means reading material that cannot execute book-supplied code or request unintended external resources.

There is no new product fork to ask the user to settle.
The two concrete technical paths below aim at the same approved reading behavior.
Neither justifies reducing the feature set to plain text.
Package approval, maintenance ownership, and Android acceptance remain the parent's decisions.

| Technical path | Existing capability | Additional ownership and cost | Assessment |
| --- | --- | --- | --- |
| Flutter wrapper 2.2.1 plus clean, pinned epub.js 0.3.93 | Existing Flutter view/controller, contents tree, CFI navigation, search, themes, text selection, local resource serving | A small package fork; request/navigation/permission policy; immutable passive resources; tested search corrections; WebView upgrades; Android accessibility acceptance | First candidate. It needs fewer new cross-language interfaces and fits the existing Flutter screen. The old epub.js release is a maintenance liability, not a claim of a modern maintained engine. |
| Readium Kotlin toolkit 3.1.2 with an EPUB-only Flutter/native bridge | Native EPUB navigator, reading preferences, publication locators, decorations, contents, and a native publication search service | Platform-view and lifecycle bridge; expose search and locator events; the same passive resource policy; Kotlin/Gradle integration and Android-specific tests | Concrete fallback if the first candidate cannot pass layout, resume, or accessibility acceptance. No native build or widget embedding was attempted here. |

Readium is pinned to commit `71074ea0c424eabbc39a93b48a4cefe366f7741b`, the toolkit version used by the inspected Flutter bridge.
This report does not claim it is the latest Readium release.
Readium's `SearchService` returns publication locators; it is a real implementation path, not a proposed custom renderer.
Its `WebViewServer` also returns no intercepted response for other hosts.
Selecting Readium alone does not enforce Bookfin's passive-content requirement.

The existing `flureadium` 0.19.6 bridge is not the recommended shortcut to Readium.
Its Flutter publication interface exposes no book-text search operation.
Its Android manifest adds an exported media service, broad media permissions, and application-wide cleartext traffic.
Its native dependencies include TTS, audio, ExoPlayer adapters, and a second PDF stack.
Its build requests SDK 35, minimum SDK 24, JVM 18, and Readium 3.1.2.
Those are integration and removal costs beside Bookfin's existing audio and pdfrx owners.
The plugin's supplied license is LGPL v3; Readium's is BSD 3-Clause.
No LGPL compliance or Android build approval is inferred.

`epub_view` 3.3.0 is ruled out as the quick repair.
It still depends on EPUBX 4 and renders individual parsed elements through `flutter_html`.
Its default image builder removes `../` text from paths and passes every selected image to `MemoryImage`.
Its link callback treats links as external callbacks.
It therefore retains the known SVG decoder failure, weakens relative-resource identity, and requires new work for publisher CSS/fonts, internal navigation, and search.
This exclusion is source inspection, not a new executable failure or a full package audit.

## What the executable evidence establishes

A CFI is an EPUB document-tree address, independent of screen pages.
DOM means a parsed document tree without a browser layout engine.
A locator is a saved location within one edition.
An edition fingerprint identifies the exact downloaded source and its processed content.

| Required behavior | Observed evidence | Work still required |
| --- | --- | --- |
| Real chapter structure and contents | Actual wrapper and engine parse EPUB2/3 chapters and resolve all supplied contents links in nine editions. Headings, Arabic language/direction markup, image alternate text, and note targets remain in the semantic EPUB. | Render full XHTML in the Android viewport. Supply reading-order entries when a source has no contents tree. The two minimal generated MOBI6 books have no source contents. |
| Text sizing and cream/sepia themes | The package supplies font-size, custom-theme, and custom-CSS APIs. Changing DOM styles does not change the tested CFI text ranges. | Real line wrapping, bundled Source Serif application, large-text settings, dark appearance, contrast, and approved chrome layout on Android. DOM style changes do not prove visual reflow. |
| Search | Nine books yield expected phrases and resolvable CFIs. Research patches additionally find a phrase crossing inline emphasis and both repeated occurrences. The clean upstream distribution passes these probes too. | Cancellable searches; visible incomplete-search errors; long fragmented phrases; Unicode case expansion; whitespace rules; exclude hidden/head text. The source multi-node search defaults to five text nodes. These probes do not certify all search semantics. |
| Stable positions and bookmarks | A search-result CFI resolves to the same text after styling and reopening a fresh engine/document. The semantic probe also resolves text after a non-BMP character. | Save the visible start CFI, not a search range or screen page, through existing records. Test process death, font/theme changes, orientation, actual page changes, and revision rejection on Android. |
| Internal links | Source contents links resolve to spine resources; a local note target resolves in the second semantic chapter. The wrapper has internal-link and footnote support. | Actual taps, return navigation, fragments with encoding, cross-chapter notes, and external-link rejection in the WebView. |
| PNG, JPEG, and fonts | Real package ZIP reads and Android-style interceptor calls on the host return the correct PNG/JPEG/font bytes and MIME types. Nested chapter/CSS/font paths resolve from each containing resource. Flutter paints both raster samples. | WebView font application and images on Android. The host resource tests do not run Android's interception callback. |
| KF8 SVG | The real SVG-to-JPEG association is identified and the conservative raster fallback paints the exact cover bytes. Fourteen active, remote, transformed, or non-wrapper variants are rejected. | Apply that rewrite inside the passive publication before navigation; display an explicit unsupported-image result for other SVG. No general SVG engine is selected. |
| Accessibility | Source headings, language/direction, alternate text, and note structure survive the DOM probe. | TalkBack reading order, focus, links, image labels, selection, large text, and avoiding duplicate Flutter/WebView semantics. Neither candidate has accessibility acceptance from this research. |
| Offline and passive content | All book data for host probes is local. No production account, token, browser, or device is used. Exact source archives are fingerprinted. | Native request denial, permission denial, CSP, immutable sanitized content, archive limits, resource MIME admission, and network-attempt tests. Offline local loading is not proof of remote-request blocking. |

The real corpus includes Alice EPUB3, French Candide EPUB3, Frankenstein MOBI6 conversion, and Moby-Dick KF8 conversion.
The Moby-Dick result contains 144 reading-order resources and 145 supplied contents links.
The other five editions are the existing generated river EPUB, two generated MOBI6 conversions, the existing real Alice KF8 conversion, and a generated semantic EPUB with a local font.
Rights and exact input hashes remain in `tool/research/readers/corpus-manifest.json` and the existing fixture provenance.
There is no private-library, encrypted-book, fixed-layout, interactive-EPUB, or universal MOBI claim.

## The SVG failure and allowed fallback

The converted Alice cover document is `OEBPS/part00000.html`.
Its image refers to `flow00004.svg`, a 324-byte SVG resource.
That SVG contains one image referring to `resource00000.jpg` in the same directory.
The JPEG is 800 by 1104 pixels.
Its SHA-256 is `2a34efaa254af4e36d509c64dc4ca5483c163da89414a3a2dcaaf3e80b331eef`.
This is a resource association, not conversion corruption.

The host Flutter test confirms that the original SVG cannot be decoded as a raster image.
The same test decodes and paints the JPEG and the independent 24-by-24 PNG fixture.
It checks the PNG's sepia center pixel and requires varied cover pixels, rather than accepting a blank opaque widget.
The two committed painted PNG files are host-test evidence, not Android screenshots.

The bounded fallback recognizes only the exact single-local-raster wrapper shape.
It rejects scripts, event attributes, network URLs, file/data URLs, parent traversal, extra vector content, transforms, CSS, document types, fragments, and changed geometry.
It checks the referenced raster's real format and dimensions.
It never evaluates or renders the SVG.
The source SVG and source raster remain available unchanged.

In production, rewrite this recognized image reference to the verified local raster resource before making the document's navigation addresses.
For other SVG, show an explicit unsupported-image label while retaining text, alternate text where available, and source resources.
That fallback is explicitly allowed by `t3-9r9u`; it is not general SVG support.
Do not add `flutter_svg` or silently skip the first image.

## Why the unmodified package is not safe

The source's resource interceptor contains this exact line:

```dart
    if (url.host != interceptHost) return null;
```

where

- `url` is the requested resource address.
- `interceptHost` is the package's reserved local-publication hostname.
- `null` means the WebView handles the request rather than receiving a denied response from Dart.

The separate navigation callback contains:

```dart
          return NavigationActionPolicy.ALLOW;
```

where `NavigationActionPolicy.ALLOW` permits the requested navigation.

These are source findings backed by a host test showing a remote address receives no intercepted response.
Another host test shows the server returns SVG event and remote-image attributes unchanged.
The corresponding desired-behavior tests fail for those exact reasons.
No external request or script execution is performed by those tests.
The engine's default no-script iframe sandbox is useful, but it is not a request allowlist or an SVG sanitizer.
Disabling all JavaScript would also disable the trusted navigator runtime.

The production resource owner must admit only the active edition's local resources and exact trusted runtime assets.
It must reject everything else, including navigations, redirects, permission requests, book-supplied scripts, frames, objects, forms, and unintended remote CSS/image/font resources.
Keep book resources separate from trusted reader scripts.
Use a tested markup sanitizer, explicit resource policy, and content-security policy, not regular-expression stripping.
Keep local publisher styles and fonts where that policy allows them.
Sanitization must finish before CFIs are issued, and the resulting document representation must remain immutable for that version.
The existing standalone HTML research filter discarded styles and SVG; it is not suitable unchanged for this reader.

Android already has a no-listening-port path in this package: resources are returned by request interception under a reserved HTTPS hostname.
No public or loopback server is needed for the primary target.
Do not use the package's URL downloader or its automatic whole-archive fallback to bypass Bookfin's verified downloads or passive resource admission.

## Source pins, fixes, and maintenance

`tool/research/readers/navigator/sources.json` pins six source archives with SHA-256.
It records the wrapper, both inspected Flutter alternatives, their interface package, the exact Readium commit, and clean epub.js 0.3.93.
The wrapper was published October 28, 2026; flureadium was published September 30, 2026.
These dates were checked through pub.dev metadata.
Recent wrapper releases do not prove current engine security or long-term maintenance.

The wrapper's bundled engine does not match the clean 0.3.93 distribution, even after newline normalization.
`epubjs-provenance.json` records both hashes.
The clean distribution passes the same ten host DOM checks before and after the bounded search corrections.
Prefer the clean, identifiable distribution for a production fork and retain its BSD 2-Clause license.
The wrapper has a BSD 3-Clause license.
This is not a complete transitive-license or security audit.

The search work has meaningful red-green evidence:

1. The original wrapper misses a visible phrase split by inline emphasis.
2. Calling the engine's existing multi-node search finds that phrase but loses matches in short documents and repeated text. The real river fixtures expose the short-document regression.
3. The bounded engine corrections examine remaining end windows and return repeated matches. Ten DOM checks then pass with the bundled engine and the clean upstream engine.

The patches are research candidates, not production code.
They patch published distribution files to make the experiment reproducible.
The production fork must port the corrections into source modules and preserve these regressions.
No engine rebuild, APK build, Android WebView, or general search certification occurred.
The wrapper also uses `flutter_inappwebview` 6.2.0-beta.3 in the resolved probe.
That beta dependency, WebView lifecycle behavior, and engine patch ownership require explicit parent review.

## Production handoff

Keep one local-publication owner for both downloaded EPUB and supported MOBI converted to EPUB.
That owner handles archive identity, passive resource admission, local relative paths, and the immutable processed document.
The renderer owns visible navigation; existing Bookfin records own saved reading positions and bookmarks.
Audio positions stay with the existing audio owner.
Do not create a second EPUBX image store or a parallel reader-position database.

Use the existing `TextPosition` fields for edition, source file, and source revision.
Its `anchor` can carry a versioned EPUB CFI payload with resource path, processed-content identity, original-file fingerprint, and quote context.
Do not replace the source revision with a screen page or conflate it with a file hash.
Include conversion and content-policy identities when they change the processed document.
The research conversion archive hash can change when generated ZIP metadata changes, so do not regenerate converted editions on every resume.
Retain the processed edition used to create its positions.
Reject or explicitly migrate incompatible positions; never silently apply one edition's bookmark to another.

The implementation sequence is:

1. Parent reviews the source-pinned candidate and the maintenance/license costs. Start `boo-9wgg` only when its prerequisites are integrated.
2. Build the single passive-publication boundary and make both security regression requirements pass. Add resource-size, path, MIME, navigation, and request-attempt tests.
3. Embed the real document viewport inside the approved reader layout. Connect contents, text sizing, themes, search, local assets, and internal links without replacing headings or paragraphs with flattened text.
4. Connect visible locations and bookmarks to existing edition-specific records. Test restoration after process death and layout changes, including quote checks and revision rejection.
5. The acceptance worker proves Android rendering, font application, TalkBack, offline reopening, local images, unsupported-SVG messaging, and no unintended requests. It owns all device work.

There is no additional user-visible layout or feature decision in this recommendation.
If Android acceptance exposes a real tradeoff between reading behaviors, return that specific fork to the parent instead of choosing it here.
The parent retains ticket closure and package approval.

`docs/research/epub-navigator-flow.html` draws this proposed production path.
Dashed boxes mark integration work that these research probes do not implement.

## Reproduction and exact limits

Run the command in `tool/research/readers/navigator/README.md` through the research Nix shell.
The runner performs one command at a time and records tool versions and resource pressure.
It verifies source and public-corpus hashes, resolves both lock files, runs the probes, and restores downloaded sources after patching them.
It never installs an application, opens a browser, contacts Jellyfin, or changes device settings.

| Check | Result |
| --- | --- |
| Conservative raster-wrapper tests | 3 pass, including 14 adversarial subcases; original meaningful red retained |
| Unmodified bundled engine DOM checks | 10 pass; inline-phrase requirement separately fails as expected |
| Clean upstream engine DOM checks | 10 pass |
| Corrected bundled engine DOM checks | 10 pass, including inline and repeated-phrase requirements |
| Corrected clean upstream engine DOM checks | 10 pass, including the same requirements |
| Flutter resource/painting checks | 7 pass |
| Unmodified package security requirements | 2 fail as expected; not waived or claimed fixed |
| Flutter/pdfrx dependency solver | Resolves without EPUBX or dependency overrides |

No coverage, mutation testing, child agents, production credentials, PR, device operations, or ticket closure are part of this work.
Generated sources, public-book downloads, and package caches remain ignored and can be removed using the README cleanup command.
The committed findings, lock files, source pins, patches, and finite evidence are sufficient to rerun the experiments.
