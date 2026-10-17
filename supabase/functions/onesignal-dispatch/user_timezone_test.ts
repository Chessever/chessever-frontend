/**
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/user_timezone_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isTimezone, timezoneFromOneSignalUser } from "./user_timezone.ts";

Deno.test("reads the phone's zone off a OneSignal user", () => {
  assertEquals(
    timezoneFromOneSignalUser({
      properties: { language: "en", timezone_id: "Asia/Baku", country: "AZ" },
      identity: { external_id: "0ad55b6e" },
    }),
    "Asia/Baku",
  );
});

Deno.test("no zone, or a zone nobody can convert to, is unknown", () => {
  assertEquals(timezoneFromOneSignalUser(null), null);
  assertEquals(timezoneFromOneSignalUser({}), null);
  assertEquals(timezoneFromOneSignalUser({ properties: {} }), null);
  assertEquals(
    timezoneFromOneSignalUser({ properties: { timezone_id: "" } }),
    null,
  );
  assertEquals(
    timezoneFromOneSignalUser({ properties: { timezone_id: "Mars/Olympus" } }),
    null,
  );
  assertEquals(
    timezoneFromOneSignalUser({ properties: { timezone_id: "'; drop" } }),
    null,
  );
});

Deno.test("real zone names pass", () => {
  for (
    const zone of ["UTC", "Europe/Warsaw", "America/Argentina/Buenos_Aires"]
  ) {
    assertEquals(isTimezone(zone), true, zone);
  }
});
