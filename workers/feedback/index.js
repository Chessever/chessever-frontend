var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.ts
var MAX_BODY = 12 * 1024 * 1024;
var MAX_PICTURE = 8 * 1024 * 1024;
var MAX_MESSAGE = 16e3;
var InvalidRequest = class extends Error {
  constructor(status) {
    super("Invalid feedback request");
    this.status = status;
  }
  status;
  static {
    __name(this, "InvalidRequest");
  }
};
function reply(status, code) {
  return Response.json({ ok: status === 200, code }, {
    status,
    headers: { "Cache-Control": "no-store", ...status === 429 ? { "Retry-After": "60" } : {} }
  });
}
__name(reply, "reply");
async function readPayload(request) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    throw new InvalidRequest(415);
  }
  if (Number(request.headers.get("content-length")) > MAX_BODY) throw new InvalidRequest(413);
  const reader = request.body?.getReader();
  if (!reader) throw new InvalidRequest(400);
  const chunks = [];
  let size = 0;
  for (; ; ) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY) {
      await reader.cancel();
      throw new InvalidRequest(413);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  chunks.length = 0;
  let payload;
  try {
    payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new InvalidRequest(400);
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new InvalidRequest(400);
  return payload;
}
__name(readPayload, "readPayload");
function picture(payload) {
  if (payload.picture == null) return null;
  if (typeof payload.picture !== "object" || Array.isArray(payload.picture)) throw new InvalidRequest(400);
  const raw = payload.picture;
  if (typeof raw.base64 !== "string" || raw.base64.length > Math.ceil(MAX_PICTURE / 3) * 4 || (raw.base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(raw.base64))) {
    throw new InvalidRequest(400);
  }
  const binary = atob(raw.base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_PICTURE) throw new InvalidRequest(413);
  const png = bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 && bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10;
  const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  const webp = bytes.length >= 12 && new TextDecoder().decode(bytes.subarray(0, 4)) === "RIFF" && new TextDecoder().decode(bytes.subarray(8, 12)) === "WEBP";
  const heic = bytes.length >= 12 && new TextDecoder().decode(bytes.subarray(4, 8)) === "ftyp" && ["heic", "heix", "hevc", "hevx", "mif1"].includes(new TextDecoder().decode(bytes.subarray(8, 12)));
  if (!png && !jpeg && !webp && !heic) throw new InvalidRequest(400);
  const extension = png ? "png" : jpeg ? "jpg" : webp ? "webp" : "heic";
  return { bytes, filename: `feedback-picture.${extension}`, mime: png ? "image/png" : jpeg ? "image/jpeg" : webp ? "image/webp" : "image/heic" };
}
__name(picture, "picture");
async function telegram(env, method, body) {
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: typeof body === "string" ? { "content-type": "application/json" } : void 0,
    body,
    // Workers reject redirect: "error" with a TypeError on every call; Telegram
    // never redirects, so a 3xx simply fails the !response.ok check below.
    redirect: "manual",
    signal: AbortSignal.timeout(1e4)
  });
  if (!response.ok) {
    await response.body?.cancel();
    return false;
  }
  const result = await response.json();
  return result.ok === true;
}
__name(telegram, "telegram");
async function deliver(env, message, attachment) {
  const fields = { chat_id: env.TELEGRAM_CHAT_ID, message_thread_id: Number(env.TELEGRAM_THREAD_ID) };
  if (attachment) {
    const body = new FormData();
    body.set("chat_id", fields.chat_id);
    body.set("message_thread_id", String(fields.message_thread_id));
    body.set("caption", Array.from(message).slice(0, 1024).join(""));
    body.set("document", new Blob([new Uint8Array(attachment.bytes).buffer], { type: attachment.mime }), attachment.filename);
    if (await telegram(env, "sendDocument", body)) {
      message = Array.from(message).slice(1024).join("");
    }
  }
  const chars = Array.from(message);
  for (let start = 0; start < chars.length; start += 4096) {
    if (!await telegram(env, "sendMessage", JSON.stringify({ ...fields, text: chars.slice(start, start + 4096).join(""), link_preview_options: { is_disabled: true } }))) return false;
  }
  return true;
}
__name(deliver, "deliver");
var index_default = {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/health" && request.method === "GET") return reply(200, "healthy");
    if (path !== "/v1/feedback") return reply(404, "not_found");
    if (request.method !== "POST") return reply(405, "method_not_allowed");
    if (request.headers.has("origin")) return reply(403, "native_clients_only");
    const ip = request.headers.get("CF-Connecting-IP");
    if (!ip) return reply(400, "missing_client_address");
    try {
      if (!(await env.PER_IP.limit({ key: ip })).success || !(await env.TOTAL.limit({ key: "feedback" })).success) return reply(429, "rate_limited");
      if (!env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_CHAT_ID || !/^\d+$/.test(env.TELEGRAM_THREAD_ID)) return reply(503, "unavailable");
      const payload = await readPayload(request);
      if (Object.keys(payload).some((key) => !["message", "picture"].includes(key)) || typeof payload.message !== "string" || !payload.message.trim() || payload.message.length > MAX_MESSAGE) throw new InvalidRequest(400);
      const sent = await deliver(env, payload.message, picture(payload));
      return sent ? reply(200, "delivered") : reply(502, "delivery_failed");
    } catch (error) {
      if (error instanceof InvalidRequest) return reply(error.status, "invalid_request");
      console.error(JSON.stringify({ event: "feedback_delivery_failed", error: String(error && error.message || error).slice(0, 200) }));
      return reply(502, "delivery_failed");
    }
  }
};
export {
  index_default as default
};
