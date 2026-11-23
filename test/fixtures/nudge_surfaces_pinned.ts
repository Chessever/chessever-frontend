// Pinned copy of NUDGE_SURFACES from chessever-admin-portal
// shared/nudges.ts, branch fix/push-routing-audit-o-items at cfa224e (admin
// PR #19), the Nudge catalog for the current phone shell. Read by
// test/nudge_marker_anchors_test.dart when the admin checkout is not beside
// this one. Refresh it (paste the array) whenever the catalog changes.
//
// OLD_SHELL / NEW_SHELL: "before 38.18 only" / "38.18 and later".

export const NUDGE_SURFACES: NudgeSurface[] = [
  { id: "home.nav.home", label: "Home", group: "Bottom bar", trail: [] },
  { id: "home.nav.feed", label: "Feed", group: "Bottom bar", trail: [], builds: NEW_SHELL },
  { id: "home.nav.botvinnik", label: "Botvinnik", group: "Bottom bar", trail: [], builds: NEW_SHELL },
  { id: "home.nav.collections", label: "Collections", group: "Bottom bar", trail: [] },
  { id: "home.menu", label: "Profile", group: "Bottom bar", trail: [] },

  ...tabs("Home", "home.tab", ["My Space", "Today", "Discovery"], HOME, OLD_SHELL),

  { id: "discovery.tile.collections", label: "Collections", group: "Discovery", trail: DISCOVERY, builds: "38.20.2 and later" },
  { id: "discovery.tile.likes", label: "Likes", group: "Discovery", trail: DISCOVERY },
  { id: "discovery.tile.news", label: "News", group: "Discovery", trail: DISCOVERY },
  { id: "discovery.tile.feed", label: "Feed", group: "Discovery", trail: DISCOVERY },
  { id: "discovery.tile.reports", label: "Reports", group: "Discovery", trail: DISCOVERY },
  { id: "discovery.tile.miniatures", label: "Miniatures", group: "Discovery", trail: DISCOVERY },

  { id: "my_space.tile.my_prep", label: "Prep", group: "My Space", trail: MY_SPACE },
  { id: "my_space.tile.library", label: "Library", group: "My Space", trail: MY_SPACE },
  { id: "my_space.tile.my_likes", label: "Likes", group: "My Space", trail: MY_SPACE },

  { id: "home.nav.events", label: "Events", group: "Profile", trail: PROFILE },
  { id: "drawer.inbox", label: "Inbox", group: "Profile", trail: PROFILE },
  { id: "drawer.board", label: "Board", group: "Profile", trail: PROFILE },
  { id: "drawer.calendar", label: "Calendar", group: "Profile", trail: PROFILE },
  { id: "drawer.rankings", label: "Rankings", group: "Profile", trail: PROFILE },
  { id: "drawer.settings", label: "Settings", group: "Profile", trail: PROFILE },
  { id: "drawer.feedback", label: "Feedback", group: "Profile", trail: PROFILE },
  { id: "drawer.rate", label: "Rate ChessEver", group: "Profile", trail: PROFILE },
  { id: "drawer.about", label: "About", group: "Profile", trail: PROFILE },
  { id: "profile.free_plan", label: "Free plan (Upgrade)", group: "Profile", trail: PROFILE, builds: `${NEW_SHELL}, readers without Premium` },
  { id: "drawer.desktop", label: "Desktop", group: "Profile", trail: PROFILE, builds: OLD_SHELL },

  ...tabs("Events list", "events.tab", ["Past", "Current", "Upcoming"], EVENTS),
  ...tabs("Rankings", "favorites.tab", ["Favorites", "Games", "Rankings"], [...PROFILE, "drawer.rankings"]),
  ...tabs("Inside an event", "event.tab", ["About", "Games", "Bracket", "Standings", "Players"]),
  ...tabs("Inside a smart event", "smart_event.tab", ["About", "Games", "Events"]),
  ...tabs("Inside a player profile", "player.tab", ["About", "Games", "Events"]),
  ...tabs("Collections", "collections.tab", ["About", "Collections", "Authors"], ["home.nav.collections"], OLD_SHELL),
  ...tabs("Inside a collection", "collection.tab", ["About", "Games", "Players"]),
  ...tabs("Inside a collection author", "author.tab", ["About", "Collections"]),
  ...tabs("Prep", "prep.tab", ["Games", "Profiles", "Players"], [...MY_SPACE, "my_space.tile.my_prep"]),
  ...tabs("Inside a Prep profile", "prep_profile.tab", ["About", "Games", "Build Tree"]),
  ...tabs("Miniatures", "miniatures.tab", ["About", "Games", "Players"], [...DISCOVERY, "discovery.tile.miniatures"]),
  ...tabs("Likes", "likes.tab", ["About", "Games", "Players"], [...DISCOVERY, "discovery.tile.likes"]),
  ...tabs("Inside Most liked", "most_liked.tab", ["Games", "Players"]),
  ...tabs("Inside Countrymen", "countrymen.tab", ["Events", "Games", "Rankings"]),

  { id: "board.bar.explorer", label: "Opening explorer button", group: "Game board", trail: [] },
  { id: "board.bar.engine", label: "Engine button", group: "Game board", trail: [] },
];
