/**
 * Favorite-player matching for onesignal-dispatch.
 *
 * The round's fide ids / names travel in a POST body (RPC), not a GET URL.
 * Results are paged until a short page — no leftover dropped. If the RPC
 * is not deployed yet, packed REST `.in()` pages are the fallback.
 */

import {
  estimatedInFilterUrlBytes,
  packForUrlBudget,
} from "./postgrest_in.ts";
import {
  describeError,
  type PostgrestResult,
  runQuery,
} from "./transient.ts";

export type FavoriteMatchRow = {
  user_id: string | null;
  fide_id: string | null;
  player_name: string | null;
};

export const FAVORITE_MATCH_PAGE = 1000;

type RpcRunner = (
  args: {
    p_fide_ids: string[];
    p_names: string[];
    p_user_ids: string[] | null;
    p_offset: number;
    p_limit: number;
  },
) => PromiseLike<PostgrestResult<FavoriteMatchRow[]>>;

type RestPage = (
  column: "fide_id" | "player_name",
  values: string[],
  from: number,
  to: number,
) => PromiseLike<PostgrestResult<FavoriteMatchRow[]>>;

export async function collectFavoriteMatches(args: {
  fideIds: string[];
  names: string[];
  userIds?: string[];
  rpc: RpcRunner;
  restPage?: RestPage;
  pageSize?: number;
}): Promise<FavoriteMatchRow[]> {
  const fideIds = [...new Set(args.fideIds.filter(Boolean))];
  const names = [...new Set(args.names.filter(Boolean))];
  if (fideIds.length === 0 && names.length === 0) return [];

  const pageSize = args.pageSize ?? FAVORITE_MATCH_PAGE;
  try {
    return await pageRpc({
      fideIds,
      names,
      userIds: args.userIds,
      rpc: args.rpc,
      pageSize,
    });
  } catch (error) {
    if (!args.restPage) throw error;
    console.error(
      `[onesignal-dispatch] favorite RPC unavailable, packed REST fallback: ${
        describeError(error)
      }`,
    );
    return await pageRest({
      fideIds,
      names,
      restPage: args.restPage,
    });
  }
}

async function pageRpc(args: {
  fideIds: string[];
  names: string[];
  userIds?: string[];
  rpc: RpcRunner;
  pageSize: number;
}): Promise<FavoriteMatchRow[]> {
  const rows: FavoriteMatchRow[] = [];
  let offset = 0;
  while (true) {
    const batch = await runQuery<FavoriteMatchRow[]>(
      "Favorite player match",
      () =>
        args.rpc({
          p_fide_ids: args.fideIds,
          p_names: args.names,
          p_user_ids: args.userIds && args.userIds.length > 0
            ? args.userIds
            : null,
          p_offset: offset,
          p_limit: args.pageSize,
        }),
    );
    const page = batch ?? [];
    rows.push(...page);
    if (page.length < args.pageSize) return rows;
    offset += page.length;
  }
}

async function pageRest(args: {
  fideIds: string[];
  names: string[];
  restPage: RestPage;
}): Promise<FavoriteMatchRow[]> {
  const rows: FavoriteMatchRow[] = [];
  for (
    const column of ["fide_id", "player_name"] as const
  ) {
    const values = column === "fide_id" ? args.fideIds : args.names;
    for (const packed of packForUrlBudget(values)) {
      let from = 0;
      while (true) {
        const to = from + FAVORITE_MATCH_PAGE - 1;
        const batch = await runQuery<FavoriteMatchRow[]>(
          `Favorite player ${column} lookup`,
          () => args.restPage(column, packed, from, to),
        );
        const page = batch ?? [];
        rows.push(...page);
        if (page.length < FAVORITE_MATCH_PAGE) break;
        from += page.length;
      }
    }
  }
  return rows;
}

export function packedPageCountFor(values: readonly string[]): number {
  return packForUrlBudget(values).length;
}

export function onePageExceedsBudget(values: readonly string[]): boolean {
  return estimatedInFilterUrlBytes(values) > 8 * 1024;
}
