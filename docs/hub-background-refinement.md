# Full-card contextual backgrounds (2026-09-28)

The user wants backgrounds filling the cards, with simple content. The previous
small corner icons and all moving likes decoration were rejected.

Feed and Reports retain the approved full-card graphics: video frames and an
analysis curve. Miniatures uses its existing rounded lightning bolt, replacing
the knight to match its screen header and Library entry. Databases now uses the existing Library
chess-database cylinder and its 2x2 checkerboard. Smart Events now uses the
existing SmartEventDeck motif of overlapping board tiles and two front squares.
The generated backgrounds were guided by raster references of those actual
source geometries, replacing the unrelated book and trophy illustrations.

Most Liked now has one static heart based on the existing heart SVG. It has no
portraits or animation and does not wait for game or player data. My Likes remains
commented out in My Space and its decorative layer remains empty.

[Updated asset paths, reference sources and exact prompts](hub-existing-icon-prompts.md).
The previous Feed, Miniatures and Reports prompts remain below.

The original full-card graphics were generated with the built-in imagegen tool and compressed
to 768 × 512 WebP. [Final asset paths and exact prompts](hub-simple-art-prompts.md).
Only bundled assets are read. Decode width is capped at 768. Old rejected images
are retained as files, but no active tile references them.

Design recheck: one subject per card, full-size artwork instead of a corner mark,
no new font or theme colors, no controls baked into the images, no entrance
animation or delayed portrait swap. Native labels, insets, clipping, and routes
remain. The miniature knight and book edges crop only decorative art. The graph
is decorative, not a claimed live evaluation. Full-card rendering and the absence
of background animation are covered by widget tests. Per repository rules, device
visual verification remains with the user; the app was not built or launched.
