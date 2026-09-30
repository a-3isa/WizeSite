# Contributing

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` a user-facing capability
- `fix:` a defect
- `test:` tests only
- `chore:` tooling, deps, or docs with no product behavior change
- `refactor:` behavior-preserving code movement

Keep the subject to one line that explains **why**. Do not paste `git status`,
file lists, or terminal dumps as the commit message.

## Tests

Match constitution III: add or update tests with the behavior change. Run
`flutter analyze`, targeted `flutter test`, and `cd functions && npm test`
before opening a PR.

## Do not

- Force-push `main`
- Point tools at production `wize-site` unless a human asked
- Commit secrets, even if they are already gitignored on disk
