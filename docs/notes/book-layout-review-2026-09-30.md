# Book cards and About layout review

Release remains held at the user's request. These changes are present in the
original local checkout and mirrored into the full-source release checkout,
based on `9c0c639b8cb8e03b2a68df584497061ecc392b98`. No new build, push, backend
deployment, or schema change was performed for this redesign.

## Changes and evidence

- Book cards use the existing collection row, palette, typography, landscape
  plate, favorite action, and context menu. Games, views, and stars form a
  wrapping metadata group. Star counts remain real server-backed counts.
- Book About uses an 80×120 jacket with `BoxFit.contain` beside the bibliographic
  identity. Description, foreword, and contributor biographies each have an
  explicit heading only when populated. The repeated generated summary is gone.
- About uses a shared 20-unit gutter, 24-unit section gaps, 8-unit heading/body
  gaps, and 12-unit paragraph gaps. Prose is capped at 640 logical pixels.
  Events and retry actions align their ink with that gutter.
- Book star and About link targets are at least 48×48 logical pixels. Opening
  the card and starring it are separate accessible actions. Text padding uses
  directional start/end behavior.
- Event visual layouts, About fields, Premium gates, game export restrictions,
  chapter/round behavior, and backend contracts remain intact.
- Secondary text contrast clears AA: 6.44:1 on light cards, 5.65:1 on
  light About, 5.33:1 on dark cards, and 5.99:1 on dark About.
- Scoped analysis passed. 85 collection widget/unit tests passed, including
  metadata alignment, separate star semantics, long counts, 320-wide RTL at
  2× text scaling in both themes, jacket proportions, and Premium flows.
- Two independent Impeccable layout assessments ran in parallel. Their final
  findings were resolved: excessive top padding was reduced to four units and
  About action padding was removed without reducing target size. The web-only
  HTML/CSS detector was deliberately skipped for this native Dart surface.

## Design-law recheck

The supplied law was rechecked in full. The following groups cover its entries
and distinguish source verification from the user's live-device review.

| Entry family | Result for this surface |
| --- | --- |
| Lucide, generic outline icon rows, redrawn line icons, missing/faked logos, logo tiles, gradient initials | No icon package, logo, avatar, or invented mark added. Existing pixel assets, eye glyph, star assets, and real jackets remain. Icons earn their place as view/favorite information. |
| Em dashes, decorative quotes, meta-criticism, generic filler | No such copy introduced. Removed the generated sentence repeating the book title; show supplied editorial text. |
| Pills, eyebrows, tinted metadata chips, floating image tags, inner-glow badges, pulsing dots | No contained metadata decorations introduced. Counts and publication details use plain type and spacing. |
| Font rotation, signature serif, letterspaced wordmark, mono as house voice, one label treatment everywhere | Preserve the user's requested native component system and documented Inter voice. No font swap, tracking costume, novelty display treatment, or wordmark introduced. Headings, credits, metadata, and body retain distinct roles. |
| Purple gradients, gradient text, pastel candy wash, candy aurora, blue-charcoal defaults, cream defaults, UI-kit gray, saturated accents, hard color seams | Existing semantic colors remain. No new background, gradient, saturated highlight, or section color boundary. Primary text and secondary metadata use the existing theme tokens in both themes. |
| Background glows, radial halos, glowy buttons, cut-off bloom, default all-around shadow, duplicate-box shadow, hard-edged shadow, blurred shape bloom | Removed the About jacket shadow and outline. Added no glow, shadow, offset slab, or luminous border. |
| Glass and botched glass, gradient icon tiles, oversized icons in tiles, accent-bar cards | No glass, tint tile, stripe, decorative badge, or accent-edge container introduced. |
| Kitchen-sink cards, floating cards, hover lift/boop, botched fills, underline-fill hover, entrance animations | Card metadata is consolidated rather than accumulated. Existing press behavior remains; no new hover or entrance animation and no content hidden pending animation. |
| Fake app windows, fake snippets, crude SVG/CSS illustrations, graph-paper grids, fixed scrolling backgrounds, decorative grain | No simulated product, invented illustration, background field, texture overlay, or fake UI added. The book itself provides the genuine visual artifact. |
| CTA pairs, pricing tiers, testimonial blocks, pre-footer banners, email-pill forms, inset enquire islands, standard/oversized footers | These marketing compositions are not applicable to this native collection surface and none were added. Existing Premium action retains its functional flow. |
| Split heroes, right-panel hero stacks, default hero stacks, kicker/H2 sections, serif statement blocks, repeated page skeletons, image-overlay cards, numbered rails, SaaS meta-template | No marketing section skeleton introduced. A small real jacket sits with bibliographic identity; paragraphs below describe that book. Section headings name actual content rather than acting as decorative kickers. |
| Clipping, clear the cut, overlapping sections, hard image seams, grain over content, edge-jammed text | Only images receive rounded clipping. About text has no fixed-height clip; list titles retain existing deliberate ellipsis. Gutters, wrapping, safe-area padding, and scrolling preserve text bounds in the layout tests. No overlapping panels or full-bleed image seams. |
| Ragged parallel columns, content flung to far edges, centering misses, off-center cut lines, cramped display type, dangling accent words | No comparison grid, strike line, display statistic, or scattered footer layout. Book text groups share a start edge; metadata wraps; action glyphs stay within their targets. Large accessibility type wraps without overflow rather than losing content. |
| Active-nav dots, stock theme toggle, dead controls, fake interactivity | No new navigation ornament or toggle. Existing tab, context-menu, favorite, unlock, related-events, and retry callbacks remain connected. Separate star semantics and Premium behavior are covered headlessly. |
| Signature artifact, atmosphere, layered depth, bespoke silhouette, treated nav, real specificity, premium toolkit and reusable components | Apply these according to the law's fit/restraint caveat and the user's explicit native-reuse direction. The real jacket, editorial text, pixel assets, and existing collection row supply product specificity. No decorative scene, marketing depth, new font, global toolkit, or unrelated navigation redesign is warranted. |
| Cohesion, repetition of house layouts, avoidance without design, lifelessness | Concrete structural decision: compact scanning in cards and a readable book identity plus editorial sections in About. Reuse is intentional because the user explicitly requested alignment with the established app. Existing functional press feedback remains; decorative motion would not help this reading surface. |

Live-app visual verification remains with the user under AGENTS.md. Check a book
card and its About tab in light/dark themes and at larger system text size. No
claim of on-device visual approval is made by these source/layout checks.

## Follow-up: card hierarchy and real editorial content

Book titles now use 16-point semibold type. The favorite control reserves space
only beside the identity header, with a centered 48-point target. Metadata uses
one flat wrapping row across the full text width; zero stars are omitted from
both visible metadata and its summary. Existing event cards retain their layout.
The two changed native source files pass scoped analysis, and the collection
layout/behavior suite passes 85 tests, including metadata alignment, separate
favorite semantics, RTL, both themes, and large text. Native release remains held
for the user's device review.

Advanced's existing published record was enriched through the existing audited
collection update service. Its subtitle and description reflect the two original
annotated 2018 PGNs, and its author credit is Vasif Durarbayli. The biography was
checked against https://durarbayli.com/ai/. Original PGNs, game identifiers,
annotations, ordering, sections, visibility, and foreword were preserved. The
published-detail read was verified after collection cache invalidation.
