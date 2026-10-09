# FlowShelf continuation entry point

Read `docs/CLAUDE-HANDOFF.md` first. It records the installed build, scope, tests,
rollback copies and remaining work. Also read `docs/OWNER-REVIEW-CHECKLIST.md`,
`docs/BUG-AUDIT-BUILD86.md` and `docs/UPGRADE-ROADMAP.md` before claiming completion.

Owner requirements:
- Research primary documentation online before implementation; inspect actual code.
- Install app changes on this Mac for owner review. Do not stop at compilation.
- Do not publish, push, tag, notarize, make a release DMG or change the appcast
  without explicit release approval. Local installation is not a public release.
- Preserve rollback app/source snapshots. Never reset this existing dirty tree.
- Do not reset permissions or delete/inspect private clipboard contents to test.
- Keep verification honest: compilation, isolated tests, offscreen renders and live
  visual approval are different. Record checks that could not be performed.
- Avoid automated live UI interaction unless the owner requests it; read-only
  process/window metadata and isolated/offscreen tests are used in this audit.
- Do not add scrolling screenshots. Keep macOS 14 support.

Do not copy credentials, signing private keys or personal clipboard data into
handoffs. No external Claude service has been sent these local files.
