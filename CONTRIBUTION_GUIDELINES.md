# Contribution Guidelines

Thanks for your interest in improving Chessever! We're an open-source friendly project and we genuinely love getting contributions from the community. Whether it's a bug fix, a new feature, a performance tweak, documentation polish, or a typo — your time and effort are appreciated.

This document explains how to contribute, what to expect from the review process, and how we decide what gets merged.

## TL;DR

- Fork the repo, branch off `main`, and open your PR against **`main`**.
- Keep PRs focused and small where possible.
- Be patient and kind — we review with care.
- We merge contributions that align with our roadmap and produce a **net-positive** impact for the app and its users.

## Where to Send Your PR

All open-source contributions should be opened as Pull Requests targeting the **`main`** branch.

We don't use a long-running `dev` branch. `main` is the source of truth, and releases are cut from it.

## How We Review Contributions

We treat every PR seriously and review it against two simple criteria:

1. **Roadmap alignment** — Does this fit where the product is heading? If you're unsure, open an issue first to discuss the idea before investing time in the implementation. We're happy to give early feedback.
2. **Net positive for the app** — Does this make Chessever better for our users without introducing meaningful regressions in performance, UX, stability, or maintainability? We weigh the upside of the change against its complexity, surface area, and long-term maintenance cost.

If a PR is great in spirit but doesn't quite fit the current roadmap, we'll explain why and, when we can, suggest a path forward (a smaller scope, a different approach, or a "park it for later" tag). We won't ghost you.

## Before You Start

- **Check open issues and PRs** to make sure no one is already working on the same thing.
- **For larger changes**, open an issue first to discuss the design. This saves everyone time.
- **For small fixes** (typos, obvious bugs, small UX improvements), feel free to send the PR directly.

## Setting Up Locally

The main `README.md` covers project setup. In short:

```bash
git clone https://github.com/Chessever/chessever-frontend
cd chessever-frontend
flutter pub get
flutter run
```

If you hit setup issues, open an issue — that's likely a documentation gap we should fix.

## Pull Request Checklist

Before opening your PR, please:

- [ ] Branch from the latest `main`.
- [ ] Keep the PR focused on one concern (separate refactors from feature work where possible).
- [ ] Run the app locally and verify your change behaves as expected.
- [ ] Update or add tests when it makes sense.
- [ ] Update relevant docs (README, inline docs, etc.) if behavior changes.
- [ ] Write a clear PR description: what, why, and how to verify.

## What Makes a Great PR Description

- **What** the change does, in one or two sentences.
- **Why** it's needed (link an issue if applicable).
- **How to test it** — steps a reviewer can follow.
- **Screenshots or screen recordings** for any UI change. This helps us review faster.
- **Trade-offs** you considered, especially for non-trivial changes.

## Code Style

- Follow the existing patterns in the codebase. When in doubt, mirror nearby code.
- Run `dart format .` before committing.
- Address analyzer warnings introduced by your change.

## Commit Messages

- Write clear, descriptive commit messages.
- Present-tense, imperative mood ("Add foo" not "Added foo").
- Reference issue numbers when relevant.

## Review Timeline

We review contributions as fast as we reasonably can, but we're a small team. If a few days pass without a response, a polite nudge on the PR is welcome.

## Bug Reports and Feature Requests

- **Bugs**: Open an issue with reproduction steps, expected vs. actual behavior, device/OS info, and screenshots if relevant.
- **Features**: Open an issue describing the problem you're trying to solve and your proposed approach. We'd rather discuss the "why" first than debate implementation details on a PR.

## Code of Conduct

Be respectful. We want this to be a welcoming place for contributors of every background and experience level. Disagreements on technical direction are fine and healthy — personal attacks are not.

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see `LICENSE`).

## Thank You

Open-source contributions are a gift. We don't take them for granted. Every typo fix, every bug report, every PR — thank you. You're helping make Chessever better for everyone who plays, studies, and follows chess with it.

Happy contributing! ♟️
