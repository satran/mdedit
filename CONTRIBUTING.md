# Contributing

Thanks for looking. MDEdit holds people's notes, so stability, speed and safety come before features.

1. Read the README, especially **Rules for changes**. It is written for coding agents and applies to people as well.
2. Build and test: `brew install xcodegen`, then `make check` (app, tests and the static audit). One test class: `make test T=NameTests`. See `TESTING.md`.
3. Keep a change small and say why in the commit message. A bug fix comes with a test that fails without it.
4. Design notes for each feature are in `docs/features/`. Open an issue before starting anything large; a feature that adds an entitlement, a network connection or a way to run code is unlikely to be accepted.

By contributing you agree that your work is released under the MIT License (see `LICENSE`).
