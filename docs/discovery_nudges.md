# Discovery Nudges and editorial destinations

Publish from Content > Nudges in the web admin. An empty marker label keeps the
breathing dot. A label such as `NEW` or `New` becomes a small word marker. Labels
preserve case and allow one word of up to 8 Unicode code points.
Icon-sized controls keep the circle when a whole word cannot fit; the word
remains available to screen readers. Words never shrink or cover a neighbour's
tap target.

Each campaign supports up to 5 tooltip messages, each containing 1-140 Unicode
code points and an optional HTTPS `See` destination. A silent campaign has no
messages. Reaching the target opens the stack with a `1/2`, `2/2` counter,
previous/next controls and an icon + See action for the current message. Messages
from different active campaigns on the same target also stack in publication
order. Reaching a trail hop only clears that hop and shows no tooltip.

The highlighted control retains its normal behavior. The message stack is shown
above the destination that control opens, and survives a drawer being removed.
Close, Back or tapping outside dismisses the tooltip. Interactive stacks do not
expire while the user is reading. A campaign is acknowledged once on reaching its
target, as before; Show again increments its revision to show it again.

Remote Config remains one production parameter, `discovery_dots`, in
`chessever-53078`. Publish the whole list after Add, Edit, Pause, Resume, Show
again or Remove. Example (illustrative, not published):

```json
{"dots":[{"id":"feature-launch","rev":1,"target":"home.tab.discovery","trail":["home.nav.home"],"label":"NEW","message":"Read the Feed.","messages":[{"body":"Read the Feed.","action_url":"https://chessever.com/feed"},{"body":"See your game reports.","action_url":"https://chessever.com/reports"}],"enabled":true,"name":"Feature launch"}]}
```

`message` retains the first tooltip's text for older app builds. Older campaigns
with only `message` continue working. Unsupported/unsafe action URLs are omitted
by the phone; publication rejects them in admin.

## Inbox and Nudge links

Inbox keeps its existing Markdown body, attached image and optional action button.
Both its Markdown links/button and Nudge See actions use
`editorialLinkOpenerProvider`. Use `https://chessever.com/` followed by one of:

| Destination | Path | Access before navigation |
| --- | --- | --- |
| Feed | `feed` | Browsable; Feed's own later-post access guard remains |
| Likes | `likes` | Browsable; opening games remains guarded |
| Miniatures | `miniatures` | Browsable; opening games remains guarded |
| Reports | `reports` | Premium prompt before opening |
| My Prep | `my-prep` | Browsable; adding/downloading stays guarded |
| Library | `library` | Existing action guards remain |
| My Likes | `my-likes` | Browsable; opening games remains guarded |
| Collections | `collections` | Browsable catalog |
| One collection | `collections/<slug>` | Current collection metadata determines Premium; re-read after unlock |
| Inbox | `inbox` | Everyone with an app session, including guests |

The page paths also accept an `app/` prefix and a trailing slash. Existing shared
game, player, broadcast, book and database URLs retain their router. Gamebase
archive game links now require Premium access before fetching/opening the game.
Other web URLs open in the browser. The app determines access; no URL query flag
can bypass the Premium check. Paid or active rewarded access skips the prompt.
Canceling it never opens the protected page or falls through to a browser.

## Device verification (user-owned)

After deploying the admin change and installing the mobile version:

1. Publish a NEW marker with two tooltip messages and different See destinations.
   Confirm case, full label, 1/2 and 2/2, previous/next, Close and outside dismissal.
2. Try a tab, a tile and a drawer row. The ordinary tap still works; the tooltip
   stays above the resulting page and the link for the current message opens.
3. As a free user, try an Inbox button and Nudge See to Reports and a Premium
   collection. Dismiss the prompt: neither destination opens. Unlock: the exact
   destination opens once. Repeat with Premium already active: no prompt.
4. Check large text, small phones, both themes and reduced motion. The tooltip
   text may scroll, but its action/navigation controls stay visible and tappable.
5. Check an older single-message campaign and a silent dot, then Show again.

No production configuration, migration or notification is changed by the local
implementation or tests. The existing rich Inbox migration is still required
for the rich admin composer.
