# Roadmap

1. Redesign + live preview + optional markers + hints. Done (35.33.2).
2. Input quality: author caps, tidy formatting, limits, remembered author. Done (35.33.3).
3. Saved progress + "Continue where you left off?". Done (35.33.4, pushed with 35.34.0).
4. Cover from gallery instead of a URL. Blocked: needs an owner-scoped cover
   upload route in the gamebase backend (only `/superadmin/collections/:id/cover`
   exists). Waiting on Berkay: which backend repo/branch, who deploys, test target.
5. Test-suite hygiene for the editor (order-dependent failure seen in
   `test/library_book_screen_test.dart`).
