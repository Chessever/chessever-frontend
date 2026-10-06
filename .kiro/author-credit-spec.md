# Author credit: publishing a collection in someone else's name

Today a published collection's author picture is always the publishing account's profile photo, and
author grouping is per account. People publish collections in the name of others, so editors must let
them credit someone else, give that author a photo (distinct from the profile photo AND the cover),
and match existing author names so one person groups together across ChessEver.

## API contract (gamebase through the same web proxy base + bearer the editor already uses)

1. PUT `<base>/api/library/folders/:id/book` accepts optional `authorCredit: "self" | "other"`.
   GET/PUT responses' `book` may include `authorCredit` ("self"|"other") and `authorPhotoUrl` (string|null).
   OLD servers omit both keys and REJECT unknown body keys with 400. So send `authorCredit` only when the
   user chose "other", or when the loaded book JSON contained the `authorCredit` key. Missing key = "self".
   Saving `authorCredit:"self"` makes the server delete any credited photo.
2. POST `<base>/api/library/folders/:id/book/author-photo` body `{"image": "<base64>"}`; DELETE same path.
   Returns the same payload as GET book. 409 `publication_unavailable` if the book was never saved (save a
   private draft first, exactly like the cover flow). Rules: JPEG/PNG/WebP, square within 1%, >=256x256,
   <=8 MB; stored 512x512 WebP. Upload sets authorCredit=other server-side. A live book goes back to review.
   Error codes -> copy:
   - author_photo_type: "Use a JPEG, PNG or WebP image."
   - author_photo_animated: "Use a still image, not an animation."
   - author_photo_aspect: "Crop the photo to a square."
   - author_photo_too_small: "Use an image at least 256 by 256 pixels."
   - author_photo_unavailable, HTTP 404/405: "Author photo uploads are not available here yet."
   - too_large, bad_base64: same copy as the cover equivalents.
3. GET `<base>/api/library/authors?name=<1-60 chars>&limit=6` ->
   `{"status":"success","data":{"items":[{"id":"credit:<32hex>","name":"Magnus Carlsen","bookCount":3,"avatarUrl":"https://...|null"}]}}`
   Existing published ChessEver authors. Any failure (404 on old servers, network) = no suggestions, silently.

## UI spec (each app in its own existing design language)

- Above the Author name field: two-option segmented control "Me" | "Someone else". Initial value from
  book.authorCredit; new books start on "Me".
- Me: name field as today. Hint says the author picture is your ChessEver profile photo. Preview uses the
  signed-in user's profile photo (Supabase user metadata `profile_avatar_url`, fallback `avatar_url`, https
  only), else a neutral person silhouette (NOT two-letter initials, NOT a gradient circle). The remembered
  author only remembers / pre-fills when the credit is "Me".
- Someone else: hint "The person who wrote or compiled it. Pick a name below if they're already on
  ChessEver so their collections stay together." After >=2 chars, debounce ~300 ms, fetch suggestions, show
  up to 6 rows (photo or silhouette, exact name, "N collections"); tapping fills the exact spelling. Ignore
  stale responses. If the typed name equals a suggestion (trimmed, case-insensitive): note "Matches an
  existing ChessEver author."
- Author photo tile (Someone else only): label "Author photo" + the existing "Optional" marker, hint "A square
  photo of the author, shown with their name in Collections. Not your profile photo." Choose -> picker ->
  crop with a 1:1 frame (generalize the cover cropper with aspect + min size params; the cover must behave
  exactly as before) -> render 512x512 -> upload immediately with a spinner -> Replace / Remove photo.
  If no own photo but the matched suggestion has avatarUrl, preview uses it with the note "Using the photo
  already on ChessEver for this author."
- Switching an "other" book that has a saved photo to "Me": inline "The saved author photo will be removed
  when you save."
- Preview shows the author picture only where the live UI really shows one; otherwise a small "Author"
  preview row in the author section (photo + name + "Shown with their name in Collections").
- The local resume-draft includes authorCredit (the photo uploads immediately, so it is not in the draft).
- Semantics labels on the segmented control, suggestion rows and photo buttons.
