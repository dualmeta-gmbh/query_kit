import Head from "@docusaurus/Head";
import Link from "@docusaurus/Link";
import useDocusaurusContext from "@docusaurus/useDocusaurusContext";
import LiveDemo from "@site/src/components/LiveDemo";
import { ogImagePath } from "@site/src/og-image-path";
import { PageMetadata } from "@docusaurus/theme-common";
import CodeBlock from "@theme/CodeBlock";
import IconCopy from "@theme/Icon/Copy";
import IconSuccess from "@theme/Icon/Success";
import Layout from "@theme/Layout";
import { useState, type ReactNode } from "react";
import styles from "./index.module.css";

// The sample is compiled: it is the region between the `landing:` markers in
// examples/doc_snippets/lib/landing.dart, and
// examples/doc_snippets/test/landing_sample_test.dart fails when the two
// differ by a character. Edit both, or neither.
const sample = `QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
    );

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return switch (tasks) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('Could not load: $error'),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final task in data) Text(task.name),
          ],
        ),
    };
  }
}`;

// The project's AI disclosure, in the one wording used everywhere a reader
// can land first (docs/plans/release-1.0-docs, D2).
const aiNotice =
  "query_kit is an entirely AI-coded project: all code, tests and documentation were written by AI coding agents (Anthropic's Claude). A human maintainer set the goals and reviews releases, but did not write the code.";

const install = "flutter pub add query_kit_flutter";

// What a search engine may read about the site and its subject (schema.org):
// the site itself, so a result is labelled with the project's name rather than
// one guessed from the domain's owner, and the source code of a Dart library,
// its repository, its packages and its licence. Google reads the `WebSite` node only on the
// home page, which is why it lives here.
function structuredData(url: string): string {
  return JSON.stringify({
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebSite",
        "@id": `${url}#website`,
        name: "query_kit",
        alternateName: ["query_kit for Flutter", "query-kit"],
        url,
        inLanguage: "en",
      },
      {
        "@type": "SoftwareSourceCode",
        name: "query_kit",
        description:
          "TanStack Query for Dart and Flutter: a port of TanStack Query's query-core with a Flutter binding. An AI-coded community port, not affiliated with TanStack.",
        url,
        codeRepository: "https://github.com/dualmeta-gmbh/query_kit",
        // The same project elsewhere, so a search engine takes the packages,
        // the repository and this site for one thing.
        sameAs: [
          "https://github.com/dualmeta-gmbh/query_kit",
          "https://pub.dev/packages/query_kit_flutter",
          "https://pub.dev/packages/query_kit",
          "https://pub.dev/packages/query_kit_hooks",
        ],
        isPartOf: { "@id": `${url}#website` },
        programmingLanguage: "Dart",
        runtimePlatform: "Flutter",
        license: "https://opensource.org/licenses/MIT",
        keywords: [
          "TanStack Query",
          "TanStack Query for Flutter",
          "React Query",
          "React Query for Flutter",
          "Flutter",
          "Dart",
          "cache",
          "data fetching",
        ],
      },
    ],
  });
}

type Feature = { title: string; body: ReactNode; to: string };

// The features in four groups, so twelve entries read as four short lists;
// each group names the API a reader will meet for it.
const featureGroups: { name: string; api: string[]; features: Feature[] }[] = [
  {
    name: "The cache",
    api: ["QueryKey", "StaleTime", "GcTime"],
    features: [
      {
        title: "Caching and deduplication",
        body: "Five widgets reading one key make one request and share its answer.",
        to: "/docs/guides/caching",
      },
      {
        title: "Stale-while-revalidate",
        body: (
          <>
            A second visit renders from the cache at once, and refetches behind
            it when the data is older than its <code>staleTime</code>.
          </>
        ),
        to: "/docs/important-defaults",
      },
      {
        title: "Refetch on focus and reconnect",
        body: "The app returning to the foreground, or the network returning, refreshes what is on screen.",
        to: "/docs/guides/window-focus-refetching",
      },
      {
        title: "Infinite and paginated lists",
        body: "Pages fetched in either direction, kept under one key, refetched in order.",
        to: "/docs/guides/infinite-queries",
      },
    ],
  },
  {
    name: "Writes",
    api: ["MutationOptions", "onMutate", "invalidateQueries"],
    features: [
      {
        title: "Mutations and invalidation",
        body: "A write names the keys it made stale, and whatever shows them fetches again.",
        to: "/docs/guides/invalidations-from-mutations",
      },
      {
        title: "Optimistic updates",
        body: "Show the write before the server answers, and roll it back when the server refuses.",
        to: "/docs/guides/optimistic-updates",
      },
    ],
  },
  {
    name: "The network",
    api: ["RetryPolicy", "context.signal", "NetworkMode"],
    features: [
      {
        title: "Retries and cancellation",
        body: (
          <>
            Failed fetches retry with backoff; a fetch whose function reads{" "}
            <code>context.signal</code> is cancelled when its last reader
            leaves.
          </>
        ),
        to: "/docs/guides/query-cancellation",
      },
      {
        title: "Offline-aware",
        body: "Told when the device is offline, queries wait for the network instead of failing, and writes made offline pause until it is back.",
        to: "/docs/guides/network-mode",
      },
    ],
  },
  {
    name: "In your code",
    api: ["context.query", "QueryBuilder", "QueryMixin"],
    features: [
      {
        title: "Four equal ways to read",
        body: (
          <>
            <code>context.query</code>, <code>QueryBuilder</code>,{" "}
            <code>QueryMixin</code> or a <code>ValueListenable</code>. None of
            them is the default.
          </>
        ),
        to: "/docs/guides/reading-queries-in-widgets",
      },
      {
        title: "Sealed results",
        body: (
          <>
            A <code>switch</code> over <code>QueryPending</code>,{" "}
            <code>QueryError</code> and <code>QuerySuccess</code> is exhaustive,
            so there is no <code>data!</code>.
          </>
        ),
        to: "/docs/dart-type-safety",
      },
      {
        title: "A pure-Dart core",
        body: "The cache runs without Flutter: in a CLI, on a server, in a shared package.",
        to: "/docs/guides/pure-dart",
      },
      {
        title: "Nothing but Flutter",
        body: (
          <>
            No hooks, signals or connectivity package required. Connectivity is
            a <code>Stream&lt;bool&gt;</code> you bring yourself.
          </>
        ),
        to: "/docs/guides/connectivity",
      },
    ],
  },
];

// Test names that appear verbatim in upstream's query-core suite (at the
// pinned revision) and in the port's; checked by grep, not by a test.
const concordance = [
  {
    name: "should go through a pending state even when the queryFn returns synchronously",
    upstream: "queryObserver.test.tsx",
    port: "query_observer_test.dart",
  },
  {
    name: "should continue retry after reconnect and resolve all promises",
    upstream: "query.test.tsx",
    port: "query_test.dart",
  },
  {
    name: "should apply the maxPages option to limit the number of pages",
    upstream: "infiniteQueryBehavior.test.tsx",
    port: "infinite_query_behavior_test.dart",
  },
];

// The two packages, as pub.dev lists them; the floors are the pubspecs'.
const packages = [
  {
    name: "query_kit_flutter",
    use: (
      <>
        For a Flutter app: the provider, controllers, builder widgets, a{" "}
        <code>State</code> mixin and <code>context.query</code>, with the core
        re-exported.
      </>
    ),
    install: "flutter pub add query_kit_flutter",
    floor: "Flutter 3.27 or later",
  },
  {
    name: "query_kit",
    use: "The pure-Dart core, for a CLI, a server, or a package shared with one.",
    install: "dart pub add query_kit",
    floor: "Dart 3.6 or later",
  },
];

function Arrow(): ReactNode {
  return <span aria-hidden="true">→</span>;
}

// An install line, with a copy button. Without a clipboard (an insecure
// origin, an old browser) the button simply does nothing; the line is still
// there to select.
function InstallCommand({ command }: { command: string }): ReactNode {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard?.writeText(command).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1600);
      },
      () => {},
    );
  };
  return (
    <div className={styles.install}>
      <span className={styles.installPrompt} aria-hidden="true">
        $
      </span>
      <code className={styles.installCode}>{command}</code>
      <button
        type="button"
        className={styles.installCopy}
        onClick={copy}
        aria-label={copied ? "Copied" : `Copy: ${command}`}
      >
        {copied ? <IconSuccess /> : <IconCopy />}
      </button>
    </div>
  );
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext();

  return (
    <Layout
      title="TanStack Query for Flutter and Dart"
      description="TanStack Query for Flutter and Dart: cached server data, background refetching, retries, mutations and infinite queries, ported test for test."
    >
      {/* Its own share image, from plugins/og-images.ts. */}
      <PageMetadata image={`/${ogImagePath(siteConfig.baseUrl, siteConfig.baseUrl)}`} />
      <Head>
        <script type="application/ld+json">
          {structuredData(siteConfig.url + siteConfig.baseUrl)}
        </script>
      </Head>
      <header className={styles.hero}>
        <div className={styles.heroBackdrop} aria-hidden="true" />
        <div className={styles.heroInner}>
          <div className={styles.heroText}>
            {/* The heading names what a reader searches for; the large line
                below it says what that buys them. */}
            <h1 className={styles.kicker}>TanStack Query for Flutter and Dart</h1>
            <p className={styles.title}>
              Server data in Flutter,{" "}
              <span className={styles.titleAccent}>
                cached and kept&nbsp;fresh
              </span>
            </p>
            <p className={styles.subtitle}>
              A port of TanStack Query to Dart and Flutter. You describe where
              the data comes from; the cache decides when to fetch, share,
              refresh and forget it.
            </p>
            <div className={styles.actions}>
              <Link
                className="button button--primary button--lg"
                to="/docs/quick-start"
              >
                Quick start
              </Link>
              <Link
                className="button button--secondary button--lg"
                to="/docs/examples"
              >
                Examples
              </Link>
              <Link className={styles.textAction} to="/docs/overview">
                Overview <Arrow />
              </Link>
            </div>
            <InstallCommand command={install} />
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="dart" title="task_list.dart">
              {sample}
            </CodeBlock>
          </div>
        </div>

        {/* Shown to every reader, not quoted as the page's search snippet;
            the AI notice in docusaurus.config.ts says why. */}
        <aside
          className={styles.disclosure}
          aria-label="About this project"
          data-nosnippet=""
        >
          <p className={styles.disclosureLabel}>Before you start</p>
          <p className={styles.disclosureText}>{aiNotice}</p>
          <p className={styles.disclosureText}>
            It is a community port of TanStack Query, and not affiliated with or
            endorsed by TanStack.{" "}
            <Link to="/docs/project/credits">Credits and what that means</Link>.
          </p>
        </aside>
      </header>

      <main>
        <section className={styles.section}>
          <h2 className={styles.heading}>Server state is not app state.</h2>
          <div className={styles.prose}>
            <p>
              A selected tab or a half-typed form is yours: it stays where you
              left it. The orders on a server are not. Someone else can change
              them, your copy ages while the user reads it, three screens want
              it at once, and the network drops at the worst moment.
            </p>
            <p>
              A <code>FutureBuilder</code> gets the first load on screen. What
              comes after is the real work: caching, sharing one request between
              readers, refreshing when the app comes back, retrying, cancelling,
              invalidating after a write, paging. query_kit does that work the
              way TanStack Query does it on the web, so a screen only says what
              it shows.
            </p>
            <p>
              <Link className={styles.textAction} to="/docs/overview">
                The longer version <Arrow />
              </Link>
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.demo}`}>
          <div className={styles.demoIntro}>
            <h2 className={styles.heading}>
              A write on screen before the server answers.
            </h2>
            <p className={styles.prose}>
              The showcase's optimistic-updates screen, running in this page
              against an in-memory backend. Add a todo and it is in the list at
              once. Then switch on <em>Refuse next write</em>, choose{" "}
              <em>Via cache</em> and add another: the row appears, the server
              refuses it, and the cache rolls back.
            </p>
          </div>
          <LiveDemo feature="optimistic-updates" height={620} />
        </section>

        <section className={styles.section}>
          <h2 className={`${styles.heading} ${styles.headingWide}`}>
            The work after the first load, done by the cache.
          </h2>
          <div className={styles.groups}>
            {featureGroups.map((group) => (
              <div key={group.name} className={styles.group}>
                <div>
                  <h3 className={styles.groupName}>{group.name}</h3>
                  <ul className={styles.groupApi}>
                    {group.api.map((name) => (
                      <li key={name}>
                        <code>{name}</code>
                      </li>
                    ))}
                  </ul>
                </div>
                <dl className={styles.features}>
                  {group.features.map((feature) => (
                    <div key={feature.title} className={styles.feature}>
                      <dt className={styles.featureTitle}>
                        <Link to={feature.to}>{feature.title}</Link>
                      </dt>
                      <dd className={styles.featureBody}>{feature.body}</dd>
                    </div>
                  ))}
                </dl>
              </div>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.fidelity}>
            <h2 className={styles.heading}>
              Upstream's own tests say it behaves the same.
            </h2>
            <div className={styles.prose}>
              <p>
                TanStack Query's test suite is ported alongside the code, under
                upstream's own test names, so the two files read side by side.
                Every case that is not ported is listed with its reason, and
                where the Dart port differs on purpose, the differences are
                written down as behaviour.
              </p>
            </div>
            <table className={styles.concordance}>
              <caption>
                Three of the ported cases, with the name they carry in both
                suites
              </caption>
              <thead>
                <tr>
                  <th scope="col">Test name</th>
                  <th scope="col">Upstream</th>
                  <th scope="col">query_kit</th>
                </tr>
              </thead>
              <tbody>
                {concordance.map((row) => (
                  <tr key={row.name}>
                    <td>{row.name}</td>
                    <td>
                      <code>{row.upstream}</code>
                    </td>
                    <td>
                      <code>{row.port}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className={styles.links}>
              <Link className={styles.textAction} to="/docs/project/fidelity">
                How fidelity is proven <Arrow />
              </Link>
              <Link
                className={styles.textAction}
                to="/docs/reference/differences-from-tanstack"
              >
                Differences from TanStack Query <Arrow />
              </Link>
            </p>
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.headingSmall}>Credits</h2>
          <div className={styles.colophon}>
            <p>
              <strong>
                Thank you to Tanner Linsley and to everyone who has built and
                maintained TanStack Query.
              </strong>{" "}
              Every good idea here is theirs, published under their MIT licence,
              whose notice each package carries in <code>LICENSE-TANSTACK</code>
              .
            </p>
            <p>
              <strong>It is not theirs.</strong> Not affiliated with, endorsed
              by, reviewed by, or connected in any way to Tanner Linsley, the
              TanStack team, or the TanStack organisation. Please do not take
              problems with this package to them;{" "}
              <a href="https://github.com/dualmeta-gmbh/query_kit/issues">
                they belong here
              </a>
              .
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.closing}`}>
          <div className={styles.closingPanel}>
            <h2 className={styles.heading}>
              Two packages on pub.dev, and an add-on.
            </h2>
            <div className={styles.packages}>
              {packages.map((pkg) => (
                <div key={pkg.name} className={styles.package}>
                  <h3 className={styles.packageName}>
                    <a href={`https://pub.dev/packages/${pkg.name}`}>
                      {pkg.name}
                    </a>
                  </h3>
                  <p className={styles.packageUse}>{pkg.use}</p>
                  <InstallCommand command={pkg.install} />
                  <p className={styles.packageFloor}>
                    {pkg.floor}. MIT licence.
                  </p>
                </div>
              ))}
            </div>
            {/* Optional, so it is a line under the two and not a third card. */}
            <p className={`${styles.prose} ${styles.addOn}`}>
              For an app written with <code>flutter_hooks</code>, the optional
              add-on{" "}
              <a href="https://pub.dev/packages/query_kit_hooks">
                <code>query_kit_hooks</code>
              </a>{" "}
              reads the same cache with <code>useQuery</code> and the rest of
              React Query's hooks.{" "}
              <Link className={styles.textAction} to="/docs/guides/hooks">
                Hooks <Arrow />
              </Link>
            </p>
            <div className={styles.actions}>
              <Link
                className="button button--primary button--lg"
                to="/docs/quick-start"
              >
                Quick start
              </Link>
              <Link className={styles.textAction} to="/docs/examples">
                Examples <Arrow />
              </Link>
              <Link className={styles.textAction} to="/docs/overview">
                Overview <Arrow />
              </Link>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
