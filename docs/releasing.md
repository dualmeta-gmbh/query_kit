# Releasing

Two packages go to pub.dev, in a fixed order, from a tag each. A third, the
hooks add-on `query_kit_hooks`, is not released yet; it has a section of its
own, [The hooks add-on](#the-hooks-add-on).

**[`scripts/release.sh`](../scripts/release.sh) walks the whole procedure.** It
is this document as a path rather than as prose: it refuses to start unless the
tree is releasable, signs the CLI in, publishes the core and then the binding in
order, waits for pub.dev in between, opens both admin pages for the
automated-publishing switch, and tags without firing the publish workflow. It is
resumable — a version already on pub.dev is skipped, not retried.

```bash
./scripts/release.sh
```

The rest of this file is what it does and why, which is what you need when a
step has to be done by hand.

**1.0.0 is released (2026-09-23).** Both packages are on pub.dev under the
verified publisher dualmeta.io, tagged `query_kit-v1.0.0` and
`query_kit_flutter-v1.0.0` at `f6b163d`, automated publishing is on for both,
and the documentation site is live. The wizard was for that bootstrap; later
releases take the path in [Later releases](#later-releases).

## Order

1. **`query_kit` first.** The binding depends on it by version, and
   pub.dev will not accept a package whose dependency it cannot resolve.
2. **`query_kit_flutter` second**, once the core version is visible on
   pub.dev (a minute or two after publishing).

The examples (`examples/showcase`, `examples/task_manager`) are never published
(`publish_to: none`).

## Before tagging

- Both `pubspec.yaml` files carry the release version (no `-dev`), and the
  binding's `query_kit` constraint names it (`^1.0.0`).
- Both `CHANGELOG.md` files have a heading for exactly that version; pub
  validates it.
- CI is green on `main` for the commit being tagged — every job of
  `ci.yml`: `gates` (the five test suites, the core's also compiled to
  JavaScript, the analyzer, the formatter, `dart doc --validate-links`,
  `dart pub publish --dry-run` for both packages, a web build of each
  example), `floors` (the suites on Flutter 3.27.4), `website` and both `e2e`
  legs. The wizard's preflight looks this up for `HEAD` and refuses a red or
  unfinished run.

## Verified publisher

Both packages are published under the verified publisher **dualmeta.io**
(Dualmeta GmbH), not under a personal account. The publisher has to exist
before the first release:

1. Verify `dualmeta.io` as a *Domain property* in the
   [Google Search Console](https://search.google.com/search-console) with the
   Google account that will publish (a DNS TXT record).
2. Create the publisher at <https://pub.dev/create-publisher> with that
   domain, signed in with the same account.
3. Add further admins under the publisher's *Members* page if more than one
   person should be able to publish.

A package's first publish lands under the signed-in account; the wizard's
stage 7 then moves both packages to the publisher from each package's admin
page (*Transfer to publisher*). Automated publishing (stage 8) is configured
on the same admin pages and is unaffected by the move.

## Tags

One tag per package, named after the package and the version:

```
query_kit-v1.0.0
query_kit_flutter-v1.0.0
```

Pushing a tag runs [`.github/workflows/publish.yml`](../.github/workflows/publish.yml),
which publishes the package under that prefix from its directory via pub.dev's
automated publishing (GitHub OIDC, no secrets). It is pub.dev's documented
*custom* workflow, not `dart-lang/setup-dart`'s reusable one: that one installs
the Dart SDK only, and both packages resolve inside the root workspace, whose
members need Flutter — the binding cannot even be validated without it. So
`setup-dart` only registers the OIDC-issued pub.dev token, Flutter is
installed after it, and `flutter pub publish --force` runs in the package's
directory. Before anything is installed it checks that the tag names the
package and version in that pubspec, and stops if not: a tag is a promise
about what is published. Every action in the workflows is pinned to a
commit SHA, its version in a comment; Dependabot's monthly `github-actions`
update moves the pin and the comment together, as a reviewable PR.
**That only works once the
package's pub.dev admin page has automated publishing enabled for this
repository and the tag pattern** — until then the workflow fails at the
publish step and nothing is published. The first publish of a new package
cannot be automated at all: it has to be `dart pub publish` by hand from the
package directory (which also creates the package), after which automated
publishing can be switched on.

**The bootstrap release costs one contortion.** Its versions are published by
hand, so pushing their tags afterwards would start `publish.yml`, which would
try to publish the same version again and fail — two red runs on the very first
release. No ordering avoids it: before the pub.dev switch is on the run fails
for want of authorization, after it for the duplicate version. So the wizard
disables the workflow, pushes the tags, and enables it again, verifying the
state on both sides and re-enabling from a trap if it exits in between. The tags
land, no run fires, and the automated path is exercised for real from the next
version on.

Manual fallback, in order:

```bash
cd packages/query_kit && dart pub publish
```

```bash
cd packages/query_kit_flutter && flutter pub publish
```

(`dart pub publish` works too when `dart` is the Flutter SDK's, which is what
the wizard assumes.)

## Later releases

From 1.0.1 on, nothing is done in a browser:

1. Bump `version` in both pubspecs (and the binding's `query_kit:` constraint
   when it needs the new core), and add a heading to both CHANGELOGs.
   Semantic versioning holds: a breaking change is a major.
2. Merge to `main` and wait for `ci` to go green there. Then run
   `native-e2e` by hand on `main` (Actions → native-e2e → Run workflow,
   "all"): the showcase's native suite and the hooks add-on's example's on
   an Android emulator, an iOS simulator, as a macOS and a Linux desktop app
   and in Chrome, and the three Playwright suites in all three browsers. It
   runs on a schedule otherwise
   — iOS and macOS only monthly, because a macOS minute costs twenty Linux
   ones — so a release is the one time it is asked for.
3. Push `query_kit-v<version>`. `publish.yml` publishes the core, and
   `pages.yml` redeploys the site.
4. Once `https://pub.dev/api/packages/query_kit` lists the new version, push
   `query_kit_flutter-v<version>`. The binding cannot resolve a core that
   pub.dev does not serve yet.

Only one of the two packages changed? Tag that one alone. The site is
redeployed on core tags only; run `pages` by hand after a binding-only
release whose docs changed.

The wizard's pre-flight is still worth running before the tags: start
`./scripts/release.sh`, let stage 1 finish, and stop with Ctrl-C at its "All
clear … Press Enter" — nothing is published before stage 4, and a new version
must not go through stage 4, which publishes by hand.

## The hooks add-on

`packages/query_kit_hooks` is a workspace member like the other two and runs
through every CI gate with them: tests on the VM and compiled to JavaScript,
`floors`, the analyzer, the formatter, `dart doc` and the publish dry-run.
What differs is how it is released (map #92, plan D17):

- **Its own version line, 0.x.** It is `0.1.0-dev` until its first release,
  0.1.0. In 0.x a breaking change is a minor (0.1 → 0.2); the rule that a
  breaking change is a major holds for it from 1.0.0 on.
- **It goes out with the binding version that first exports
  `package:query_kit_flutter/adapter.dart`, 1.1.0, on the same day.** Until
  then `adapter.dart` stays on `main` unpublished, so a binding release cut
  from `main` in between would publish it early.
- **Before tagging**, the hooks' `query_kit_flutter:` constraint goes from
  `^1.0.3` to `^1.1.0`. In the workspace it resolves to the checkout's
  binding, so nothing but the published package would notice the old lower
  bound — pana's lower-bound check would, against 1.0.3 on pub.dev.
- **The first publish is by hand,** as for any new package: binding 1.1.0
  through its tag and `publish.yml` first, then, once pub.dev serves it,

  ```bash
  cd packages/query_kit_hooks && flutter pub publish
  ```

  then *Transfer to publisher* (dualmeta.io) and automated publishing for
  the tag pattern `query_kit_hooks-v{{version}}` on its admin page. The tag
  `query_kit_hooks-v0.1.0` is pushed with `publish.yml` disabled, the
  contortion [Tags](#tags) describes. `scripts/release.sh` does not cover it.
- **Later releases** are a `query_kit_hooks-v<version>` tag, as for the
  other two, after the binding version it needs is on pub.dev.

## Documentation site

The site under `website/` is deployed to GitHub Pages at
<https://query-kit.dualmeta.io/>, live demos included, by
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml). What has to be
true for that, all of it set on 2026-09-23:

- **Settings → Pages → Source: GitHub Actions.**
- **Settings → Environments → `github-pages` → deployment branches and
  tags:** the branch `main` *and* the tag pattern `query_kit-v*`. GitHub
  creates the environment allowing `main` only, and a run started by a tag is
  then rejected at the deploy step with "not allowed to deploy to
  github-pages due to environment protection rules" — the first release hit
  exactly that. From the command line:

  ```bash
  gh api -X POST repos/dualmeta-gmbh/query_kit/environments/github-pages/deployment-branch-policies -f name='query_kit-v*' -f type=tag
  ```

- **When it runs:** on every `query_kit-v*` tag, and by hand (Actions →
  `pages` → Run workflow, on `main`). Its build is the `ci` workflow's
  `website` job step for step, demos from `tool/build_demos.sh` included, so
  what CI tested is what ships. A failed deploy is retried with *Re-run
  failed jobs*; the built artifact is kept.
- **Settings → Pages → Custom domain: `query-kit.dualmeta.io`**, with
  *Enforce HTTPS* (since 2026-10-15). DNS holds a `CNAME` from
  `query-kit.dualmeta.io` to `dualmeta-gmbh.github.io`. With an Actions-built
  site the domain lives only in this setting — a `CNAME` file in the
  artifact is ignored — and GitHub redirects the former
  `https://dualmeta-gmbh.github.io/query_kit/` there. From the command line:

  ```bash
  gh api -X PUT repos/dualmeta-gmbh/query_kit/pages -f cname=query-kit.dualmeta.io
  gh api -X PUT repos/dualmeta-gmbh/query_kit/pages -F https_enforced=true
  ```

- **The URL is set once.** `url` and `baseUrl` come from constants at the
  top of `website/docusaurus.config.ts` (the site sits at the domain's root,
  `baseUrl: '/'`), and the live demos' base href is derived from them; a
  move is one edit there plus the setting above.

## What the archives hold

- **Tests and `test/PORTING_NOTES.md` ship.** There is no `.pubignore` in the
  core: the notes are the fidelity audit (some 425 KB, the archive about
  400 KB compressed), the CHANGELOG points readers at them, and a user who
  `dart pub unpack`s the package can run the ported suite against the very
  version they depend on. Halving the download is not worth losing that
  (REL-21, 2026-09-23).
- **The binding's example resolves from pub.dev alone.** It is not a
  workspace member — a published `resolution: workspace` fails outside this
  repository (REL-7) — and it reaches the checkout through a committed
  `example/pubspec_overrides.yaml`, which the binding's `.pubignore` keeps out
  of the archive. After a fresh clone, `flutter pub get` in
  `packages/query_kit_flutter/example` resolves it; CI does that before the
  analyzer.
- **The hooks package's example ships without its end-to-end suites.** It
  resolves as the binding's does, through an `example/pubspec_overrides.yaml`
  the hooks' `.pubignore` keeps out. The same file keeps out `e2e/`,
  `e2e-native/`, `integration_test/`, `test_driver/` — they need the
  showcase's backend and device control — and the platform folders, which
  `flutter create .` writes for whoever runs it; it writes no template
  `test/widget_test.dart`, because the example's own is there. Also kept out:
  `test/repository_test.dart`, which compares the seed with the showcase
  server's and the suites with the package's hooks. The widget tests and the
  in-memory half of the contract test ship and run.
- **The hooks package's fence test stays home.** `test/docs_fences_test.dart`
  reads the site's hooks guide from `website/`, which an archive does not
  have, so the hooks' `.pubignore` keeps it out. The twins it checks, under
  `test/doc_twins/`, ship and run like any other test.
- **Throwaway probe tests** (`packages/*/test/_*_tmp_test.dart`) are
  gitignored, so they neither dirty the tree the wizard checks nor reach an
  archive.

## Naming

**The names are `query_kit` and `query_kit_flutter`, and that is the
decision** (2026-09-10). A name on pub.dev is permanent — the policy has no
way to free one — so it was deliberately left until last rather than picked
first; everything else was made ready around it in the meantime. The
candidates, which names were free, what the MIT licence obliges and what
TanStack has and has not said about ports are in
[`docs/research/package-naming-and-affiliation.md`](research/package-naming-and-affiliation.md).

Moving them is still one command, and it is the same command that produced
them, so the path stays exercised:

```bash
dart run tool/rename_packages.dart --core <core> --flutter <core>_flutter
```

It rewrites the pubspecs, every import, every path that carries the name and
every mention in prose, moves the two package directories and their library
entrypoints, and drops the stale `.dart_tool` so the first `pub get` after it
is honest. It deliberately leaves
`docs/research/package-naming-and-affiliation.md` alone: the names in that
table are a record of what pub.dev held on 2026-09-08, not references to this
package. Run the full gate afterwards — the names reach the tests, the
examples, both workflows and the website.
