export type FavoriteMapLoader = (
  roundId: string,
  userIds: Set<string>,
) => Promise<Map<string, string[]>>;

type RoundCacheEntry = {
  loadedUserIds: Set<string>;
  favoritesByUserId: Map<string, string[]>;
};

/**
 * Shares successful favorite-map results across rows from the same round in one
 * dispatcher invocation. Empty results are cached too; failed loads are not.
 */
export class RoundFavoriteCache {
  private readonly rounds = new Map<string, RoundCacheEntry>();

  constructor(private readonly loader: FavoriteMapLoader) {}

  async resolve(
    roundId: string,
    userIds: Set<string>,
  ): Promise<Map<string, string[]>> {
    let entry = this.rounds.get(roundId);
    if (!entry) {
      entry = {
        loadedUserIds: new Set<string>(),
        favoritesByUserId: new Map<string, string[]>(),
      };
      this.rounds.set(roundId, entry);
    }

    const missingUserIds = [...userIds].filter(
      (userId) => !entry.loadedUserIds.has(userId),
    );
    if (missingUserIds.length > 0) {
      const loaded = await this.loader(roundId, new Set(missingUserIds));
      for (const userId of missingUserIds) entry.loadedUserIds.add(userId);
      for (const [userId, favorites] of loaded) {
        entry.favoritesByUserId.set(userId, favorites);
      }
    }

    const result = new Map<string, string[]>();
    for (const userId of userIds) {
      const favorites = entry.favoritesByUserId.get(userId);
      if (favorites) result.set(userId, favorites);
    }
    return result;
  }
}
