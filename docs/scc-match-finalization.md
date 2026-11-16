# SCC match finalization, 16 November 2026

Nakamura beat Erdogmus 12–8 in 20 games. The organizer's results page shows
the score, but its winner overrides remain empty and the quarterfinal player
still reads “Winner C”. The broadcast contains no quarterfinal game yet.

Source: https://www.chess.com/events/2026-speed-chess-championship/results

The production tour `fqCjSUpE` now carries the confirmed result and official
seed order in `info.matchPlayBracket`. The targeted update required exactly
20 terminal games with Nakamura scoring 12 in round `60IswAYI`, and changed
only that JSON key. It preserved the event, schedule, games and future rounds.
The regression fixture `test/fixtures/scc_final_20261116.json` records that
snapshot and the metadata contract. No participant identity or match length
is hardcoded into the clients.

The next stage `qhktidXj` therefore shows Nakamura in quarterfinal 2, awaiting
the winner of Nihal Sarin–Niemann. The new cards are presentation only, with
no games, scores or click action. Source pairings replace them once published.

Finalization requires an explicit confirmed result. Do not infer one from
all current games having results: the next game is appended after the previous
one ends, including long breaks between time-control segments. Future confirmed
finals can use the same result shape; normal later-round pairing evidence
continues to advance players without this metadata.
