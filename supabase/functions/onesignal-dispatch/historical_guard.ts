/** Scope only. The shared SQL notification_replay_reason function owns policy. */
export const HISTORICAL_EVENT_TYPES = new Set([
  "game_started",
  "game_finished",
  "round_started",
  "round_finished",
]);
