# Board image import: device checks

The import is additive to Board and Position Setup. It reads one JPEG, PNG or WebP, aligns four board corners locally, calls the new board-scan Worker with the current ChessEver session, and opens the detected position for review. No provider key is bundled. Castling/en passant are cleared; the user selects side to move and rotates the actual detected position as needed.

The new Worker must first be configured and deployed from the Cloudflare PR. Native `BOARD_SCAN_API_BASE_URL` and web `NEXT_PUBLIC_BOARD_SCAN_API_URL` can select its preview URL. Recognition still makes piece-type mistakes on real photos.

Validation completed: scoped flutter analyze and FEN/rotation/homography tests. No flutter build/run or live-app attachment was used, per repository rules.

## Check on device

1. Open Board and tap Import image. Try both Gallery/Upload and Camera. Deny camera access once, then use an upload instead.
2. Select a diagram, align the four handles to the outer squares, choose Diagram and Read position. Repeat with a physical-board photo and Photo selected.
3. Rotate the detected position 90° until a1/h8 match your image; choose the side to move. Compare every occupied square and correct any misidentified pieces in the editor.
4. Apply/Analyze, play moves, navigate the notation, copy FEN/PGN and use the normal Board actions. Confirm existing import/setup flows still work.
5. Cancel at source choice, crop, during reading and during review. Confirm the active board is not replaced. Close camera preview and confirm the camera light turns off.
6. Try an unreadable file, an oversized image, signed-out/expired-session scans, and an unavailable/429 endpoint. Confirm a readable error and a working retry/cancel.
7. Check a small window, both themes, enlarged text and keyboard navigation. The crop handles and action labels must remain whole and readable.

Desktop: repeat on both macOS and Windows. Drop one image into the tappable drop zone, click it to open a file dialog, and try the camera. Lower-resolution cameras fall back to their default mode. macOS declares only the camera permission added by this feature; no microphone track is requested.
