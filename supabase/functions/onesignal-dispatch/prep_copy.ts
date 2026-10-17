/**
 * The words of a starred Prep player's daily "new games" push.
 *
 * The count is deliberately left out: the push says that the player played
 * and roughly how much, and the reader taps to see the number. The app
 * shows it on the profile the push opens (data `added`).
 */
export type PrepGamesCopy = { title: string; body: string };

/** [name] as the profile is called, [added] how many new games it got. */
export function prepGamesAddedCopy(
  name: string,
  added: number,
): PrepGamesCopy {
  const who = name.trim() || "Your player";
  if (added >= 20) {
    return {
      title: `${who} could not stop playing`,
      body: "A big batch of new games is in your prep. Tap to see how many.",
    };
  }
  if (added >= 5) {
    return {
      title: `${who} had a busy day`,
      body: "Fresh games are waiting in your prep. Guess how many?",
    };
  }
  return {
    title: `${who} played today`,
    body: "New games just landed in your prep. See what they played.",
  };
}
