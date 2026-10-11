import Head from '@docusaurus/Head'
import Link from '@docusaurus/Link'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import LiveDemo from '@site/src/components/LiveDemo'
import CodeBlock from '@theme/CodeBlock'
import Layout from '@theme/Layout'
import { useState, type ReactNode } from 'react'
import styles from './index.module.css'

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
}`

// The project's AI disclosure, in the one wording used everywhere a reader
// can land first (docs/plans/release-1.0-docs, D2).
const aiNotice =
  "query_kit is an entirely AI-coded project: all code, tests and documentation were written by AI coding agents (Anthropic's Claude). A human maintainer set the goals and reviews releases, but did not write the code."

const install = 'flutter pub add query_kit_flutter'

// What a search engine may read as the page's subject: the source code of a
// Dart library, its repository and its licence (schema.org).
function structuredData(url: string): string {
  return JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'SoftwareSourceCode',
    name: 'query_kit',
    description:
      "TanStack Query for Dart and Flutter: a port of TanStack Query's query-core with a Flutter binding. An AI-coded community port, not affiliated with TanStack.",
    url,
    codeRepository: 'https://github.com/dualmeta-gmbh/query_kit',
    programmingLanguage: 'Dart',
    runtimePlatform: 'Flutter',
    license: 'https://opensource.org/licenses/MIT',
    keywords: ['TanStack Query', 'React Query', 'Flutter', 'Dart', 'cache', 'data fetching'],
  })
}

// Stroke icons on a 24-unit grid, drawn in the current colour.
const icons = {
  copy: (
    <>
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </>
  ),
  check: <path d="M20 6 9 17l-5-5" />,
  info: (
    <>
      <circle cx="12" cy="12" r="10" />
      <path d="M12 16v-4" />
      <path d="M12 8h.01" />
    </>
  ),
} satisfies Record<string, ReactNode>

type IconName = keyof typeof icons

function Icon({ name, className }: { name: IconName; className?: string }): ReactNode {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true">
      {icons[name]}
    </svg>
  )
}

type Feature = { title: string; body: ReactNode; to: string }

const features: Feature[] = [
  {
    title: 'Caching and deduplication',
    body: 'Five widgets reading one key make one request and share its answer.',
    to: '/docs/guides/caching',
  },
  {
    title: 'Stale-while-revalidate',
    body: (
      <>
        A second visit renders from the cache at once, and refetches behind it when the data is older than its{' '}
        <code>staleTime</code>.
      </>
    ),
    to: '/docs/important-defaults',
  },
  {
    title: 'Refetch on focus and reconnect',
    body: 'The app returning to the foreground, or the network returning, refreshes what is on screen.',
    to: '/docs/guides/window-focus-refetching',
  },
  {
    title: 'Mutations and invalidation',
    body: 'A write names the keys it made stale, and whatever shows them fetches again.',
    to: '/docs/guides/invalidations-from-mutations',
  },
  {
    title: 'Optimistic updates',
    body: 'Show the write before the server answers, and roll it back when the server refuses.',
    to: '/docs/guides/optimistic-updates',
  },
  {
    title: 'Infinite and paginated lists',
    body: 'Pages fetched in either direction, kept under one key, refetched in order.',
    to: '/docs/guides/infinite-queries',
  },
  {
    title: 'Retries and cancellation',
    body: (
      <>
        Failed fetches retry with backoff; a fetch whose function reads <code>context.signal</code> is cancelled when
        its last reader leaves.
      </>
    ),
    to: '/docs/guides/query-cancellation',
  },
  {
    title: 'Offline-aware',
    body: 'Told when the device is offline, queries wait for the network instead of failing, and writes made offline pause until it is back.',
    to: '/docs/guides/network-mode',
  },
  {
    title: 'Four equal ways to read',
    body: (
      <>
        <code>context.query</code>, <code>QueryBuilder</code>, <code>QueryMixin</code> or a{' '}
        <code>ValueListenable</code>. None of them is the default.
      </>
    ),
    to: '/docs/guides/reading-queries-in-widgets',
  },
  {
    title: 'Sealed results',
    body: (
      <>
        A <code>switch</code> over <code>QueryPending</code>, <code>QueryError</code> and <code>QuerySuccess</code>{' '}
        is exhaustive, so there is no <code>data!</code>.
      </>
    ),
    to: '/docs/dart-type-safety',
  },
  {
    title: 'A pure-Dart core',
    body: 'The cache runs without Flutter: in a CLI, on a server, in a shared package.',
    to: '/docs/guides/pure-dart',
  },
  {
    title: 'Nothing but Flutter',
    body: (
      <>
        No hooks, signals or connectivity package required. Connectivity is a <code>Stream&lt;bool&gt;</code> you
        bring yourself.
      </>
    ),
    to: '/docs/guides/connectivity',
  },
]

// Test names that appear verbatim in upstream's query-core suite (at the
// pinned revision) and in the port's; checked by grep, not by a test.
const concordance = [
  {
    name: 'should go through a pending state even when the queryFn returns synchronously',
    upstream: 'queryObserver.test.tsx',
    port: 'query_observer_test.dart',
  },
  {
    name: 'should continue retry after reconnect and resolve all promises',
    upstream: 'query.test.tsx',
    port: 'query_test.dart',
  },
  {
    name: 'should apply the maxPages option to limit the number of pages',
    upstream: 'infiniteQueryBehavior.test.tsx',
    port: 'infinite_query_behavior_test.dart',
  },
]

function Arrow(): ReactNode {
  return <span aria-hidden="true">→</span>
}

// The install line, with a copy button. Without a clipboard (an insecure
// origin, an old browser) the button simply does nothing; the line is still
// there to select.
function InstallCommand(): ReactNode {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    navigator.clipboard?.writeText(install).then(
      () => {
        setCopied(true)
        setTimeout(() => setCopied(false), 1600)
      },
      () => {},
    )
  }
  return (
    <div className={styles.install}>
      <span className={styles.installPrompt} aria-hidden="true">
        $
      </span>
      <code className={styles.installCode}>{install}</code>
      <button
        type="button"
        className={styles.installCopy}
        onClick={copy}
        aria-label={copied ? 'Copied' : 'Copy install command'}>
        <Icon name={copied ? 'check' : 'copy'} />
      </button>
    </div>
  )
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext()

  return (
    <Layout
      title="TanStack Query for Dart and Flutter"
      description="TanStack Query for Flutter and Dart: cached server data, background refetching, retries, mutations and infinite queries, ported test for test.">
      <Head>
        <script type="application/ld+json">{structuredData(siteConfig.url + siteConfig.baseUrl)}</script>
      </Head>
      <header className={styles.hero}>
        <div className={styles.heroInner}>
          <div className={styles.heroText}>
            <h1 className={styles.title}>
              Server data in Flutter, <span className={styles.titleAccent}>cached and kept&nbsp;fresh</span>
            </h1>
            <p className={styles.subtitle}>
              A port of TanStack Query: queries, mutations and infinite lists for Dart, with a Flutter binding that
              needs nothing but Flutter. You describe where the data comes from; the cache decides when to fetch,
              share, refresh and forget it.
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/docs/quick-start">
                Get started
              </Link>
              <Link className="button button--secondary button--lg" to="/docs/examples">
                Examples
              </Link>
              <Link className={styles.textAction} to="/docs/overview">
                Overview <Arrow />
              </Link>
            </div>
            <InstallCommand />
            <ul className={styles.facts}>
              <li>
                <a href="https://pub.dev/packages/query_kit_flutter">query_kit_flutter</a>
              </li>
              <li>
                <a href="https://pub.dev/packages/query_kit">query_kit</a>
              </li>
              <li>Dart 3.6+</li>
              <li>Flutter 3.27+</li>
              <li>MIT</li>
            </ul>
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="dart" title="task_list.dart">
              {sample}
            </CodeBlock>
          </div>
        </div>

        <aside className={styles.disclosure} aria-label="About this project">
          <Icon name="info" className={styles.disclosureIcon} />
          <div className={styles.disclosureBody}>
            <p className={styles.disclosureLabel}>Before you start</p>
            <p className={styles.disclosureText}>{aiNotice}</p>
            <p className={styles.disclosureText}>
              It is a community port of TanStack Query, and not affiliated with or endorsed by TanStack.{' '}
              <Link to="/docs/project/credits">Credits and what that means</Link>.
            </p>
          </div>
        </aside>
      </header>

      <main>
        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>The problem</h2>
          <div className={styles.problem}>
            <p className={styles.lede}>Server state is not app state.</p>
            <div className={styles.prose}>
              <p>
                A selected tab or a half-typed form is yours: it stays where you left it. The orders on a server are
                not. Someone else can change them, your copy ages while the user reads it, three screens want it at
                once, and the network drops at the worst moment.
              </p>
              <p>
                A <code>FutureBuilder</code> gets the first load on screen. What comes after is the real work:
                caching, sharing one request between readers, refreshing when the app comes back, retrying,
                cancelling, invalidating after a write, paging. query_kit does that work the way TanStack Query does
                it on the web, so a screen only says what it shows.
              </p>
              <p>
                <Link className={styles.textAction} to="/docs/overview">
                  The longer version <Arrow />
                </Link>
              </p>
            </div>
          </div>
        </section>

        <section className={`${styles.section} ${styles.demoSection}`}>
          <h2 className={styles.sectionLabel}>Try it</h2>
          <div className={styles.demo}>
            <div className={styles.demoIntro}>
              <p className={styles.lede}>A write on screen before the server answers.</p>
              <p className={styles.prose}>
                The showcase's optimistic-updates screen, running in this page against an in-memory backend. Add a
                todo and it is in the list at once. Then switch on <em>Refuse next write</em>, choose{' '}
                <em>Via cache</em> and add another: the row appears, the server refuses it, and the cache rolls back.
              </p>
            </div>
            <LiveDemo feature="optimistic-updates" height={620} />
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>What you get</h2>
          <p className={`${styles.lede} ${styles.ledeWide}`}>The work after the first load, done by the cache.</p>
          <dl className={styles.features}>
            {features.map((feature) => (
              <div key={feature.title} className={styles.feature}>
                <dt className={styles.featureTitle}>
                  <Link to={feature.to}>{feature.title}</Link>
                </dt>
                <dd className={styles.featureBody}>{feature.body}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className={styles.section}>
          <div className={styles.fidelity}>
            <h2 className={styles.sectionLabel}>Ported, not inspired by</h2>
            <div className={styles.problem}>
              <p className={styles.lede}>Upstream's own tests say it behaves the same.</p>
              <div className={styles.prose}>
                <p>
                  TanStack Query's test suite is ported alongside the code, under upstream's own test names, so the
                  two files read side by side. Every case that is not ported is listed with its reason, and where the
                  Dart port differs on purpose, the differences are written down as behaviour.
                </p>
                <p className={styles.links}>
                  <Link className={styles.textAction} to="/docs/project/fidelity">
                    How fidelity is proven <Arrow />
                  </Link>
                  <Link className={styles.textAction} to="/docs/reference/differences-from-tanstack">
                    Differences from TanStack Query <Arrow />
                  </Link>
                </p>
              </div>
            </div>
            <table className={styles.concordance}>
              <caption>Three of the ported cases, with the name they carry in both suites</caption>
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
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Credits</h2>
          <div className={styles.colophon}>
            <p>
              <strong>Thank you to Tanner Linsley and to everyone who has built and maintained TanStack Query.</strong>{' '}
              Every good idea here is theirs, published under their MIT licence, whose notice each package carries in{' '}
              <code>LICENSE-TANSTACK</code>.
            </p>
            <p>
              <strong>It is not theirs.</strong> Not affiliated with, endorsed by, reviewed by, or connected in any way
              to Tanner Linsley, the TanStack team, or the TanStack organisation. Please do not take problems with this
              package to them;{' '}
              <a href="https://github.com/dualmeta-gmbh/query_kit/issues">they belong here</a>.
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.next}`}>
          <Link className={styles.nextLink} to="/docs/quick-start">
            <span className={styles.nextKicker}>Start</span>
            <span className={styles.nextTitle}>
              Quick start <Arrow />
            </span>
          </Link>
          <Link className={styles.nextLink} to="/docs/examples">
            <span className={styles.nextKicker}>Browse</span>
            <span className={styles.nextTitle}>
              Examples <Arrow />
            </span>
          </Link>
          <Link className={styles.nextLink} to="/docs/overview">
            <span className={styles.nextKicker}>Read</span>
            <span className={styles.nextTitle}>
              Overview <Arrow />
            </span>
          </Link>
        </section>
      </main>
    </Layout>
  )
}
