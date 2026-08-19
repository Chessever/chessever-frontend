/** In-isolate guard so a crawl cannot turn every photo into a Postgres hit. */

const WINDOW_MS = 10_000;
const GLOBAL_DB_LIMIT = 80;
const PER_IP_LIMIT = 20;
const MEM_TTL_MS = 5 * 60_000;
const MEM_MAX = 4_000;

let windowStart = 0;
let globalDb = 0;
const ipDb = new Map<string, number>();

type MemRow = { exp: number; body: unknown };
const mem = new Map<string, MemRow>();

export function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const last = xff.split(",").pop()?.trim();
    if (last) return last;
  }
  return req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown";
}

export function allowDatabaseWork(ip: string): { ok: boolean; reason?: string } {
  const now = Date.now();
  if (now - windowStart >= WINDOW_MS) {
    windowStart = now;
    globalDb = 0;
    ipDb.clear();
  }
  const nextIp = (ipDb.get(ip) ?? 0) + 1;
  ipDb.set(ip, nextIp);
  globalDb += 1;
  if (nextIp > PER_IP_LIMIT) return { ok: false, reason: "ip" };
  if (globalDb > GLOBAL_DB_LIMIT) return { ok: false, reason: "global" };
  return { ok: true };
}

export function memGet(key: string): unknown | null {
  const row = mem.get(key);
  if (!row) return null;
  if (row.exp < Date.now()) {
    mem.delete(key);
    return null;
  }
  return row.body;
}

export function memSet(key: string, body: unknown): void {
  if (mem.size >= MEM_MAX) {
    const first = mem.keys().next().value;
    if (first !== undefined) mem.delete(first);
  }
  mem.set(key, { exp: Date.now() + MEM_TTL_MS, body });
}
