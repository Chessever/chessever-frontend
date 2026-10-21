/**
 * Push image URL validation.
 * Run: deno test supabase/functions/onesignal-dispatch/push_image_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pushImageUrl } from "./push_image.ts";

Deno.test("an https image URL is passed on", () => {
  const url =
    "https://example.supabase.co/storage/v1/object/public/editorial-inbox/2026/a.webp";
  assertEquals(pushImageUrl(url), url);
  assertEquals(pushImageUrl(`  ${url}  `), url);
});

Deno.test("anything a device should not fetch is dropped", () => {
  for (
    const value of [
      undefined,
      null,
      42,
      "",
      "   ",
      "http://example.com/a.png",
      "data:image/png;base64,AAAA",
      "/storage/a.png",
      "https://user:secret@example.com/a.png",
      "https://localhost/a.png",
      "https://example.com/a b.png",
      `https://example.com/${"a".repeat(2000)}`,
    ]
  ) {
    assertEquals(pushImageUrl(value), null);
  }
});
