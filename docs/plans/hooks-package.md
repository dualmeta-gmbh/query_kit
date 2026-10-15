# Plan: `query_kit_hooks` — React-Query-Hooks auf `flutter_hooks`

**Stand:** 2026-10-15. Überarbeitet nach je einem Review durch Astra (Codex
CLI) und Fable und nach dem Spike (AP0). Das
[Review-Protokoll](#review-protokoll) am Ende sagt, welcher Befund
reproduziert wurde und was aus ihm geworden ist.

**Entscheider:** der Agent als Product Owner, von Christian am 2026-10-15
dazu bestimmt („du löst mich hiermit als Entscheider ab“). Damit ist auch
der Vorbehalt von [#21](https://github.com/dualmeta-gmbh/query_kit/issues/21)
übertragen, der API-Fragen der Bindung Christian vorbehielt. Jede
Entscheidung unten nennt die Optionen, die Antwort und den Grund. So lässt
sie sich allein aus diesem Dokument wieder öffnen (Regel von Map #1,
„AFK“).

**Grundlage:**

- Die Klassifikation aller 298 Fälle der Hook-Suiten von
  `@tanstack/react-query` am Pin `50680b98c`, in
  [`docs/research/react-query-hook-tests-inventory.md`](../research/react-query-hook-tests-inventory.md).
  Die Zahlen dort sind Einordnungen beim Lesen, keine Messungen. Wo die
  Inventur eine Umsetzung vorschlägt, gilt dieser Plan.
- Der Spike, in [`docs/research/hooks-spike.md`](../research/hooks-spike.md):
  45 Tests, alle grün. Seine Messungen stehen bei den Entscheidungen, die
  sie betreffen.

---

## Ziel und Umfang

**Ziel.** Ein eigenes, optionales Paket `query_kit_hooks`. Mit ihm schreibt
ein Flutter-Entwickler, der `flutter_hooks` benutzt, seine Queries so, wie
er es aus React Query kennt:

```dart
class TaskTile extends HookWidget {
  const TaskTile({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final task = useQuery(taskQuery(id));
    final rename = useMutation(renameTask());
    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('$error'),
      QuerySuccess(:final data) => ListTile(
          title: Text(data.title),
          onTap: () => rename.mutate((id: id, title: 'Neu')),
        ),
    };
  }
}
```

Was das Paket von einem dünnen Wrapper unterscheidet, ist dasselbe wie beim
Kern: **Die Upstream-Suiten der Hooks werden Fall für Fall portiert.** Die
Inventur zählt etwa 258 portierbare Fälle: 146 direkt, 105 angepasst und 7
Lücken, die dieser Plan schließt, eine davon nur teilweise. Dazu kommen 9
Prefetch-Fälle.

**Drin:**

- `useQuery` und `useSelectQuery`
- `useInfiniteQuery`
- `useMutation`
- `useQueries`, dazu `useCombinedQueries`. Der baut nur neu, wenn sich das
  kombinierte Ergebnis ändert oder das, worauf sein `retry`/`refetch`
  wirkt.
- `useIsFetching`, `useIsMutating`, `useMutationState`, `useQueryClient`
- `usePrefetchQuery`, `usePrefetchInfiniteQuery`
- Portierte Suiten mit eigenen `PORTING_NOTES`
- Doku-Seite, README, Beispiel-App, Repo- und CI-Integration
- Ein Release

**Nicht drin.** Die Gründe stehen in D14.

- Suspense-Hooks und `HydrationBoundary`
- `QueryErrorResetBoundary` und `throwOnError`
- `IsRestoringProvider`
- `subscribed`: steht im Backlog als HB-1
- `skipToken`
- `retryOnMount` als Callback
- Ein `combine` über die rohen Ergebnisse
- Callback-Kontext für Mutationen
- Jede Änderung am Kern `query_kit`, die kein reproduzierter Fehler erzwingt

**Randbedingung.** Kern und Bindung werden nicht nennenswert umgebaut. Die
Bindung bekommt eine neue Bibliothek, `adapter.dart`, mit einer einzigen
Klasse, `RebuildRule` (D4). Ihr interner `ReadEntry` benutzt diese Regel
dann selbst. Der Kern bekommt nichts.

---

## Ausgangslage

- **Bindung.** `query_kit_flutter` 1.0.4 hat vier gleichrangige
  Aufrufstile: Controller, Builder, `QueryMixin` und `context.query`.
  - Alle Controller sind `ValueListenable`.
  - Ihre Lebensdauer regelt `ControllerLifetime`. Dass sie nicht doppelt
    benachrichtigen, regelt `NotifyGate`.
  - Ob neu gebaut wird, entscheidet die interne Klasse `ReadEntry`:
    - Der beobachtete Zustand entspricht dem gebauten: kein Rebuild.
    - Nur die Hälfte neben dem Ergebnis hat sich bewegt (die Paging-Flags):
      Rebuild.
    - Sonst entscheidet `buildWhen(gebaut, aktuell)`.
  - `ReadEntry` besitzt seinen Controller und entsorgt ihn (`dispose` castet
    auf `ChangeNotifier`).
- **`context.query` liest flach im `build`.** Das kommt einem Hook schon
  nahe. Es hängt aber am `QueryScope` des Providers und ordnet Controller
  über den `QueryKey` (oder eine `id`) zu, nicht über die Aufrufposition.
- **Benachrichtigungen.**
  - Der Standard-Scheduler des Kerns ist `scheduleMicrotask`.
  - Der Provider installiert einen eigenen: im Build zurückgestellt bis
    nach dem Frame, sonst synchron.
  - `NotifyManager.flush` behält bereits eingereihte Zustellungen, auch wenn
    das Abo inzwischen weg ist. Wer direkt abonniert, muss sich gegen späte
    Zustellungen selbst schützen. Die Controller tun das über
    `ControllerLifetime`.
- **Die Website lehnt Hooks bisher ab.**
  - Der Abschnitt „Signals, hooks and other reactive packages“
    (`website/docs/guides/reading-queries-in-widgets.md`) sagt: „not planned
    as such“.
  - Die Installationsseite sagt: kein `flutter_hooks` als Abhängigkeit.
  - Beides bleibt für die zwei bestehenden Pakete richtig. Die Seiten müssen
    aber auf das neue Zusatzpaket verweisen (AP9).
- **`flutter_hooks` 0.21.x**, gemessen am Quelltext von 0.21.2 und
  0.21.3+1. In den hier genannten Teilen sind beide gleich.
  - `initHook`, `didUpdateHook` und `HookState.build` laufen alle im
    `build` des Widgets.
  - `dependOnInheritedWidgetOfExactType` löst in `initHook` eine Assertion
    aus.
  - Wirft `initHook`, ist der State verloren, weil er nie in die Hook-Liste
    kommt.
  - **Wirft der Build, wird ab dem Cursor entsorgt:**
    - Wirft der `build` eines Hooks X, werden X und alle folgenden
      entsorgt. Der Cursor rückt erst weiter, wenn `build` zurückkehrt.
    - Wirft der Widget-Body nach X, werden nur die noch nicht erreichten
      Hooks entsorgt.
    - Ein Wurf nach dem letzten Hook entsorgt nichts.
  - Beim `unmount` läuft erst `super.unmount`, dann `dispose` jedes Hooks.
    In `dispose` ist `context.mounted` also schon `false`.
  - `Hook` hat kein `==`, also läuft `didUpdateHook` bei jedem Build.
    Ausgenommen ist eine identische Instanz, etwa ein `const`-Hook: Dann
    läuft es nicht.
  - Geänderte `keys` entsorgen den Hook und bauen ihn neu. **Ein Feld
    namens `keys` an einer Hook-Unterklasse überschreibt `Hook.keys`** und
    löst genau das aus. Im Spike passiert, und vom Analyzer gefunden.
  - `HookState.setState` prüft nicht, ob der State schon entsorgt ist.
  - `use()` innerhalb von `HookState.build` nimmt den Zweig für
    Typ-Mismatch: Er entsorgt den laufenden Hook und alle folgenden, dann
    wirft er `StateError`
    (flutter_hooks [#215](https://github.com/rrousselGit/flutter_hooks/issues/215)).
  - Ein `setState` in `useEffect` läuft während des Builds und geht
    verloren.
  - Untergrenzen: 0.21.3+1 verlangt Flutter `>=3.32.0`, 0.21.2 nur
    `>=3.21`. Der `floors`-Job (3.27.4) löst also 0.21.2 auf, Stable löst
    0.21.3+1 auf. Das `lib/` der beiden unterscheidet sich nicht in
    `framework.dart`.
  - Lizenz MIT. Letztes Release 2025-08-19. Über 1.0 wird in
    [#486](https://github.com/rrousselGit/flutter_hooks/issues/486)
    gesprochen. Die Abkopplung von `material` in Flutter 3.47 betrifft das
    Paket ([#491](https://github.com/rrousselGit/flutter_hooks/issues/491)).
- **Die Inventur.** 298 Fälle, Ergebnis je Datei:

  | Datei | Fälle | P | A | N | G |
  |---|---|---|---|---|---|
  | `useQuery.test.tsx` | 155 | 84 | 43 | 14 | 14 |
  | `useInfiniteQuery.test.tsx` | 28 | 6 | 22 | 0 | 0 |
  | `useQueries.test.tsx` | 24 | 3 | 12 | 3 | 6 |
  | `queryOptions`/`infiniteQueryOptions` | 2 | 0 | 0 | 2 | 0 |
  | `useMutation.test.tsx` | 61 | 38 | 17 | 4 | 2 |
  | `useMutationState.test.tsx` | 5 | 0 | 5 | 0 | 0 |
  | `useIsFetching.test.tsx` | 5 | 1 | 4 | 0 | 0 |
  | `QueryClientProvider.test.tsx` | 4 | 3 | 1 | 0 | 0 |
  | `mutationOptions.test.tsx` | 14 | 11 | 1 | 2 | 0 |
  | **Summe** | **298** | **146** | **105** | **25** | **22** |

  - P = direkt portierbar, A = mit Anpassung, N = gehört nicht hierher,
    G = Lücke.
  - Dazu kommen `usePrefetchQuery.test.tsx` (6 Fälle) und
    `usePrefetchInfiniteQuery.test.tsx` (3 Fälle). Alle neun bauen auf
    Suspense. Etwa vier lassen sich ohne Suspense anpassen. Die übrigen
    prüfen Suspense-Verhalten (Endlosschleife, Wasserfall, Reset der
    Error-Boundary) und sind N.
  - Beide Reviews haben die Zählung und alle Zeilennummern der Tabelle
    unten nachgezählt und für richtig befunden.

**Die 22 Lücken (G) und was aus ihnen wird:**

| Fälle | Lücke | Entscheidung |
|---|---|---|
| useQuery 738, 2016, 2055, 2109, 2159 | `notifyOnChangeProps` und verfolgte Felder | Werden zu A: `buildWhen` am Hook (D8) |
| useQueries 871 | Rebuild nur bei geändertem `combine`-Ergebnis | Wird zu A: `useCombinedQueries` (D10) |
| useQueries 490 | dasselbe, mit Teil-Ergebnissen | **Teilweise A.** Die Invariante „ein Refetch mit gleichen Daten baut nicht neu“ wird portiert. Die drei ersten Ausgaben (leer, teilweise, vollständig) nicht: `CombinedResult` bleibt `pending`, bis jede Quelle Daten hat (D10) |
| useQuery 5921, 5966, 6002, 6031; useQueries 66 | `subscribed` | Backlog HB-1, gilt für alle Aufrufstile. Hier als ausgelassen notiert |
| useQueries 817 | `combine` über rohe Ergebnisse | Ausgelassen: `CombinedResult` ist die bewusste Form (#82) |
| useQuery 7054; useQueries 1195, 1251 | `isRestoring` | Ausgelassen: kein Persister (#15) |
| useQuery 6539 | `skipToken` | Ausgelassen: `Enabled.no` deckt den Zweck |
| useQuery 6786 | Warnung bei fehlendem `queryFn` | Ausgelassen: der Kern scheitert mit `MissingQueryFunctionError` |
| useQuery 6973, 7004 | `retryOnMount` als Callback | Ausgelassen: Kernoption ist `bool?`. Der übrige Teil von 7004 wird portiert |
| useMutation 2533, 2555 | Callback-Kontext | Ausgelassen: Divergenz #14/#83 |

Sieben Lücken werden portierbar, 490 davon nur teilweise. 15 bleiben als
begründete Auslassung.

---

## Entscheidungen

### D1 — Ein Zusatzpaket auf `flutter_hooks`

- **Optionen:**
  - (a) Hooks in `query_kit_flutter` selbst.
  - (b) Ein eigenes Hook-Gerüst in der Bindung, ohne `flutter_hooks`.
  - (c) Ein eigenes Paket, das von `flutter_hooks` abhängt.
- **Antwort:** (c).
- **Warum:**
  - (a) bricht Christians Regel aus #21: Das Hauptpaket verlangt kein
    Drittpaket. Dieselbe Regel nennt Hooks ausdrücklich als „später als
    opt-in-Paket“.
  - (b) erfindet `flutter_hooks` neu. Es wäre mit dem Ökosystem nicht
    verträglich (`HookConsumerWidget`, eigene Hooks der Nutzer) und läge
    trotzdem in der Bindung.
  - (c) ist genau die Form, die #21 offen ließ.

### D2 — Name `query_kit_hooks`

- **Optionen:** `query_kit_hooks`, `query_kit_flutter_hooks`,
  `hooks_query_kit`.
- **Antwort:** `query_kit_hooks`. Am 2026-10-15 auf pub.dev frei geprüft,
  ebenso `query_kit_flutter_hooks`. Vor dem ersten Publish (AP12) wird das
  noch einmal geprüft.
- **Warum:**
  - Das Präfix `query_kit_` hält die Familie zusammen, auf pub.dev und
    alphabetisch.
  - „flutter“ im Namen sagt nichts mehr: `flutter_hooks` gibt es nur für
    Flutter.
  - Der kürzere Import zählt bei einem Paket, das man in jede Datei mit
    Widgets holt.
  - `hooks_riverpod` stellt das Wort „hooks“ voran. Das folgt Riverpods
    Familie, nicht unserer.

### D3 — Abhängigkeiten, Untergrenzen, Re-Export

- **Abhängigkeiten:**
  - `flutter_hooks: ^0.21.2`. Die Untergrenze Flutter 3.27.4 löst 0.21.2
    auf, Stable löst 0.21.3+1 auf (Ausgangslage). Beide laufen in CI. Keine
    Lockdatei darf den `floors`-Job auf 0.21.3+1 festlegen.
  - `query_kit_flutter: ^1.1.0`. 1.1.0 ist die Version mit `adapter.dart`
    (D4). Sie wird zusammen mit diesem Paket veröffentlicht (D17).
  - `query_kit` **nicht** direkt. Das Paket importiert alles über die
    Barrel-Datei der Bindung, die den Kern re-exportiert. So bleibt eine
    Versionsgrenze weniger synchron zu halten.
  - SDK `^3.6.0`, Flutter `>=3.27.0`: dieselben Untergrenzen wie die
    Bindung, und der `floors`-Job prüft sie.
- **Re-Export:** Die Bibliothek exportiert `query_kit_flutter`, wie
  `hooks_riverpod` `flutter_riverpod` exportiert. `flutter_hooks` exportiert
  sie **nicht**.
- **Warum:**
  - Ein Import für alles, was query_kit betrifft.
  - Wer `HookWidget` schreibt, hängt ohnehin selbst von `flutter_hooks` ab
    (`depend_on_referenced_packages`).
  - Würden wir es mit exportieren, würde seine API Teil unserer
    SemVer-Zusage.

### D4 — Die Naht: `RebuildRule` in `package:query_kit_flutter/adapter.dart`

- **Optionen:**
  - (A) Nur öffentliche API. Die Rebuild-Regel wird im Hook-Paket
    nachgebaut.
  - (B) Eine neue öffentliche Bibliothek `adapter.dart` exportiert
    `ReadEntry`, `ObservedState` und `observedStateOf`.
  - (B′) `adapter.dart` exportiert nur eine besitzfreie Regel,
    `RebuildRule<T>`. `ReadEntry` benutzt sie intern selbst.
  - (C) Die Regel in den Kern verschieben.
- **Antwort:** (B′). Der Spike lief auf (A).
- **Gemessen (Spike, Messung 2):**
  - Eine Regel von 32 Codezeilen trägt alle Hooks. Jeder Hook gibt ihr
    seinen Wert und seinen beobachteten Zustand als Closures:
    - der Wert bei Query und Mutation;
    - der öffentliche `observedState`-Record beim Infinite-Hook;
    - ein elementweiser Wrapper des Hook-Pakets bei Liste, Kombination
      und Mutation-State.
  - `ObservedState` und `observedStateOf` braucht kein Hook.
  - Die Fläche von `adapter.dart` ist damit genau eine Klasse:
    `RebuildRule<T>` mit `read()` und `shouldRebuild(buildWhen)`.
- **Warum:**
  - Die Rebuild-Regel ist der Teil der Bindung, an dem die meisten
    Review-Befunde hingen (C49, V-B-1 bis V5). Zwei Kopien laufen
    auseinander. (A) bleibt deshalb nur der Weg des Spikes.
  - (B) ist ungesund (Astra H-06). `ReadEntry` nimmt jedes
    `ValueListenable` an, castet beim `dispose` aber auf `ChangeNotifier`
    und entsorgt es. Ein gültiges eigenes `ValueListenable` scheitert also
    erst spät mit einem Cast-Fehler. Die interne Konvention „wer übergibt,
    übergibt den Besitz“ würde zur API-Pflicht.
  - (B′) trennt die Entscheidung vom Besitz. Abo, Controller und Entsorgen
    bleiben beim Aufrufer. Die Regel liegt an einem Ort, weil `ReadEntry`
    sie benutzt, statt sie zu enthalten.
  - (C) zieht Flutter-Begriffe in einen Kern ohne Flutter und ändert ihn
    ohne Not.
- **Folge:**
  - `adapter.dart` fällt unter SemVer. Ihre Dartdoc sagt, für wen sie ist.
  - Eine Änderung an `RebuildRule` ist eine Major-Version der Bindung.
    Deshalb wird 1.1.0 erst zusammen mit dem Hook-Paket veröffentlicht,
    nachdem die Reviews aus AP11 die Fläche gelesen haben (D17, Fable
    P2-4).
  - ADR-0004 hält die Entscheidung fest (AP1).

### D5 — So funktioniert ein Hook

- **Optionen:**
  - (a) `useEffect` und `useState` aus `flutter_hooks` zusammensetzen.
  - (b) Eine eigene `Hook`-Klasse mit `HookState`, der Controller entsteht
    in `initHook`.
  - (c) Eine eigene `Hook`-Klasse, die alles in `HookState.build` erledigt.
- **Antwort:** (c), mit diesen Regeln:
  1. **Kein `keys`, kein `==` am Hook.**
     - Ein Schlüsselwechsel ist `setOptions` am selben Controller (D6),
       kein neuer Hook.
     - Kein Feld einer Hook-Klasse heißt `keys`. Ein solches Feld
       überschreibt `Hook.keys` (Ausgangslage). Der öffentliche Parameter
       `keys:` von `useCombinedQueries` landet deshalb im Feld
       `combineKeys`.
  2. **Nichts in `initHook`.** Der Client kommt im `build` aus
     `hook.client ?? QueryClientProvider.of(context)`. Eine Assertion oder
     ein Wurf in `initHook` würde den State verlieren.
  3. **Bei jedem `build`:**
     - Client abgleichen. Ein anderer Client entsorgt den Controller und
       baut einen neuen, wie bei den Buildern.
     - Sonst `setOptions` aufrufen. Unveränderte Optionen bewegen nichts,
       weil `Defaulted*Options` Wertgleichheit haben.
     - Den gelesenen Zustand über `RebuildRule.read()` als „gebaut“ merken.
  4. **Rebuild sofort im Listener entscheiden**, mit
     `RebuildRule.shouldRebuild(hook.buildWhen)`. `hook` ist dort der Hook
     des letzten Builds. Dann `setState`.
     - Die Alternative ist `markMayNeedRebuild`: Dann entscheidet der Hook
       erst beim Frame, in `shouldRebuild`. Das spart einen Build bei A→B→A
       innerhalb eines Frames. Aber `flutter_hooks` garantiert nicht, dass
       `shouldRebuild` überhaupt läuft.
     - Gewählt ist der Listener, weil `ReadEntry` für alle vier Aufrufstile
       genau dort entscheidet („one decision shared by every call style“).
       So zählen Hook und Builder dieselben Builds, und die Erwartungen aus
       den Suiten der Bindung gelten auch für die Hooks.
  5. **Jede Zustellung prüft, ob der Hook-State noch lebt, nicht nur
     `context.mounted`** (Astra H-03).
     - `HookState.setState` hat keine solche Prüfung. Nach einem Wurf vor
       dem Hook ist der State entsorgt, das Element aber noch gemountet.
     - Controller-Hooks sind durch das Entfernen des Listeners und durch
       `ControllerLifetime` geschützt.
     - Direkte Abos (D12) tragen eine Generation und ein Disposed-Flag. Beide
       werden geprüft, wenn die eingereihte Zustellung läuft. Ein Wechsel des
       Clients und `dispose` erhöhen die Generation.
     - Der Spike reproduziert die späte Zustellung. Ohne den Schutz gibt es
       einen zusätzlichen Build (Messung 8).
  6. **`dispose`:** erst den Listener entfernen, dann den Controller
     entsorgen. `context` wird dort nicht angefasst, denn `dispose` läuft
     nach `super.unmount`.
  7. **DevTools:** `debugLabel` und `debugValue` setzen.
  8. **`use()` nie innerhalb von `HookState.build`.** Ein Hook, der einen
     anderen braucht, ruft ihn als Funktion vor seinem eigenen `use()` auf.
     Sonst entsorgt `flutter_hooks` den laufenden Hook und alle folgenden,
     bevor es wirft (Ausgangslage).
- **Warum:**
  - (a) läuft in die Falle aus der Ausgangslage: `useEffect` läuft
    während des Builds, und ein `setState` darin geht verloren.
  - (b) scheitert an der Assertion beim Nachschlagen des Providers in
    `initHook`.
  - (c) ist das Muster, das die Builder seit den Reviews vom 2026-10-15
    haben: Abgleich oben in `build`, Wurf als gewöhnlicher Build-Fehler.
- **Die „+1-Build-Falle“:** Ein Hook, der im `build` Optionen anwendet,
  darf auf eine Benachrichtigung, deren Wert dem zuletzt gebauten gleicht,
  nicht neu bauen. Das deckt der erste Schritt der Regel. Gemessen: kein
  zusätzlicher Build (Spike, Messung 5).
- **Geteilt mit den Buildern, nicht erreichbar:** Fable (P3-8) nennt eine
  Benachrichtigung, während das Element bei einem `GlobalKey`-Umzug inaktiv
  ist. `markNeedsBuild` verwirft sie dann.
  - Inaktiv ist ein Element aber nur innerhalb der Build-Phase eines Frames.
  - Zustellungen kommen in dieser Phase nie synchron: Der Provider stellt
    sie zurück, ohne Provider ist es eine Microtask.
  - Der Spike-Test zum `GlobalKey`-Umzug ist grün.

### D6 — Identität über die Aufrufposition

- **Optionen:**
  - (a) Wie `context.query`: über `QueryKey` oder `id`.
  - (b) Wie React: über die Position des Aufrufs in `build`.
- **Antwort:** (b).
- **Warum:**
  - Das ist das Hook-Modell, und `flutter_hooks` erzwingt es ohnehin.
  - Ein neuer Schlüssel an derselben Position ist dieselbe Komponente mit
    anderer Query. Upstream wechselt dann per `observer.setOptions` die
    Query am selben Observer.
  - Nur über denselben Observer kann
    `placeholderData: (previous) => previous` die Daten der alten Query
    weiter zeigen. Die Fälle 1185, 1606 und 5056 prüfen genau das und sind
    im Spike grün.
  - Ein neuer Controller pro Schlüssel würde das zerstören.

### D7 — Woher der Client kommt

- **Antwort:**
  - Jeder Hook hat einen optionalen Parameter `client:`, so wie upstream
    `queryClient?`. Fehlt er, gilt `QueryClientProvider.of(context)`.
  - Ein Wechsel des Clients baut den Controller neu.
  - **`useQueryClient()`** gibt den Client des Providers zurück.
- **Warum:** So halten es die Builder schon. Fälle mit eigenem Client
  laufen in einer `MaterialApp` ohne Provider, wie die Inventur festhält.
- **Folge ohne Provider:**
  - Der Kern stellt dann über seinen Standard-Scheduler zu, eine Microtask.
    Eine Microtask läuft nie mitten in einem synchronen Build, also gibt es
    auch ohne Provider kein „setState during build“.
  - Es fehlt nur die synchrone Zustellung außerhalb eines Builds. Das kostet
    eine Microtask Verzögerung, im Test ein zusätzliches `pump()`. Die
    Builder verhalten sich genauso.
  - (Die erste Fassung behauptete, ohne Provider fehle der Schutz. Beide
    Reviews haben das widerlegt.)

### D8 — Rebuilds und `buildWhen`

- **Antwort:**
  - Jeder Hook, der ein einzelnes Ergebnis liest, nimmt
    `BuildWhen<…>? buildWhen` mit genau dem Typ der Bindung:
    - `useQuery` und `useSelectQuery`: `BuildWhen<QueryResult<TData>>`
    - `useInfiniteQuery`: `BuildWhen<QueryResult<TData>>`. Eine Bewegung
      nur der Paging-Flags baut immer neu, wie bei `ReadEntry`.
    - `useMutation`: `BuildWhen<MutationResult<TData, TVariables>>`
  - `useQueries` nimmt **keins**. Begründung wie bei `QueriesBuilder`: Ein
    Prädikat über die ganze Liste sagt nicht, welche Query sich bewegt hat.
  - `useCombinedQueries` nimmt eins über das `CombinedResult` (D10).
- **Warum:**
  - Damit werden die fünf `notifyOnChangeProps`-Fälle portierbar.
  - #15 hat entschieden, dass `buildWhen` in Dart `notifyOnChangeProps` und
    die verfolgten Felder ersetzt. Ein Hook bekommt kein zweites Konzept.
- **Takt der Frames:**
  - React rendert nicht einmal pro Benachrichtigung. Es bündelt
    Aktualisierungen: 2316 erwartet zwei Renderings für zwei Observer.
  - In den Tests mit Fake-Timern rendert React aber nach jedem
    Timer-Makrotask. Flutter baut einmal pro Frame, und ein
    `tester.pump(d)` ist ein Frame für alle Timer in `d`.
  - Die Portierung pumpt deshalb gestaffelt, eine Millisekunde pro Frame
    (`advance` im Harness).
  - **Gemessen (Spike, Messung 1):** Mit einem einzigen `pump(d)`
    scheitern 2 von 21 useQuery-Fällen (1932, 4100). Gestaffelt scheitert
    keiner, und keine Zählung musste sich ändern. Die einzige geänderte
    Zählung ist 490, durch D10 gewollt.
  - Weicht eine Zählung trotz Staffelung ab, wird die Assertion angepasst
    und in den `PORTING_NOTES` begründet. Das Hook-Verhalten wird dafür
    nicht verbogen.
  - Der Harness zeichnet Übergänge am Observer getrennt von den Builds auf
    (Astra H-02). Sonst könnte das Bündeln im Frame einen Zwischenzustand
    verschlucken, der am Observer falsch war.

### D9 — Die Hooks und was sie zurückgeben

| Hook | Rückgabe | Spiegelt |
|---|---|---|
| `useQuery<TData>(QueryObserverOptions<TData>, {buildWhen, client})` | `QueryResult<TData>` | `context.query` |
| `useSelectQuery<TQueryData, TData>(QuerySelectOptions<…>, {buildWhen, client})` | `QueryResult<TData>` | `context.selectQuery` (ADR-0001) |
| `useInfiniteQuery<TPageData, TPageParam, TData>(InfiniteQueryObserverOptionsBase<…>, {buildWhen, client})` | `InfiniteQueryController<…>` | `context.infiniteQuery`, `InfiniteQueryBuilder` |
| `useMutation<TData, TVariables, TOnMutateResult>(MutationOptions<…>, {buildWhen, client})` | `MutationController<…>` | `context.mutation` |
| `useQueries<TQueryData, TData>(List<QueryObserverOptionsBase<…>>, {client})` | `List<QueryResult<TData>>` | `QueriesBuilder` |
| `useCombinedQueries<TQueryData, TData, R>(queries, combiner, {required keys, buildWhen, client})` | `CombinedResult<R>` | neu, D10 |
| `useIsFetching({filters, client})` | `int` | `IsFetchingController`, D12 |
| `useIsMutating({filters, client})` | `int` | neu, D12 |
| `useMutationState<TSelected>({filters, required select, client})` | `List<TSelected>` | `MutationStateController` |
| `useTypedMutationState<TData, TVariables, TOnMutateResult, TSelected>(…)` | `List<TSelected>` | `MutationStateController.typed` |
| `useQueryClient()` | `QueryClient` | `QueryClientProvider.of` |
| `usePrefetchQuery<TData>(QueryOptions<TData>, {client})` | `void` | neu, D11 |
| `usePrefetchInfiniteQuery<TPageData, TPageParam>(InfiniteQueryOptions<…>, {client})` | `void` | neu, D11 |

- **Grundsatz:** Ein Hook gibt zurück, was der entsprechende flache
  Aufrufstil der Bindung zurückgibt. Wer von `context.query` kommt, lernt
  nichts Neues. Die Doku kann denselben Code zeigen.
- **`useInfiniteQuery` gibt den Controller zurück, nicht ein Ergebnis.**
  - Paging-Flags und `fetchNextPage` liegen am Controller, so wie bei
    `context.infiniteQuery`.
  - Ein Record aus Ergebnis und Controller wäre ein neuer Typ für denselben
    Zweck.
  - Die portierten Fälle lesen die Flags je Build vom Controller.
- **`useMutation` gibt den `MutationController` zurück.**
  - Er hat `value`, `mutate`, `mutateAsync`, `reset` und `cancel`.
  - `dispose` bricht die Mutation nicht ab, wie upstream: Eine Mutation
    überlebt ihr Widget.
- **`useMutationState`** geht über `MutationStateController` und dessen
  `setOptions({filters, select})`, aufgerufen bei jedem Build.
  - Filter und `select`, die bei jedem Build neu sind, erzeugen weder ein
    neues Abo noch einen Build (Spike, Messung 11).
  - Es verlangt `select`, wie der Controller. Upstream wählt als Standard
    `mutation.state`. In Dart müsste `TSelected` dann ein fester
    `MutationState<Object?, …>` sein. Angepasste Fälle übergeben
    `(m) => m.state`.

### D10 — `useCombinedQueries`: Rebuild nur bei geändertem Ergebnis

- **Optionen:**
  - (a) Ein `combine` über die rohen Ergebnisse,
    `R Function(List<QueryResult<TData>>)`, mit Rebuild bei
    `R`-Ungleichheit nach Structural Sharing. Das entspricht upstream.
  - (b) Ein `combiner` über die Werte mit `CombinedResult<R>` als
    Rückgabe. Rebuild, wenn sich das `CombinedResult` oder das, worauf seine
    Aktionen wirken, ändert und das optionale `buildWhen` zustimmt.
  - (c) Keiner. Wer kombinieren will, ruft `useQueries` und
    `results.combine(…)` im `build` auf.
- **Antwort:** (b).
- **Warum:**
  - #82 hat entschieden, dass ein `CombinedResult` die Zustandslogik trägt
    (pending, error, data, Refetch-Fehler) und nicht jeder Aufrufer sie
    selbst schreibt. Der Hook bekommt kein zweites `combine` mit anderer
    Bedeutung.
  - (c) baut für jede Query neu, die sich bewegt. Genau das schließen die
    Fälle 490 und 871 aus.
- **Das Gate (Astra H-01):**
  - **Gleichheit des Werts reicht nicht.** Die Gleichheit von
    `CombinedResult` sieht nur Variante, Fetch-Flags und den ersten Fehler.
    `retry()` wirkt aber auf die erfassten Quellen, die gerade fehlschlagen,
    und `refetch()` auf alle erfassten Quellen.
  - Beispiel: A und B schlagen fehl, dann repariert ein `setQueryData` B.
    Das neue `CombinedError(errorA)` gleicht dem gebauten. Ein Gate nur auf
    dem Wert behielte das alte `retry`, das B mit abruft. Das ist ADR-0003:
    „value equality does not imply callback ownership equality“.
  - **Deshalb ist der beobachtete Zustand ein Paar:** das `CombinedResult`
    und je Quelle `(isError, refetch)`.
  - Hat sich nur die Aktionshälfte bewegt, wird ohne `buildWhen` neu
    gebaut, so wie `ReadEntry` bei den Paging-Flags. Der gebaute Wert ist
    dann zwar gleich, aber seine Aktionen sind veraltet.
  - Gemessen: Der Spike reproduziert das Beispiel. Mit dem Wert allein
    scheitert der Test (Messung 7).
- **Umsetzung:**
  - Der Hook hält ein `CombineMemo<R>`. Im `build` ruft er
    `controller.value.combine(combiner, memo: _memo, keys: keys)` auf.
  - Der Listener rechnet mit `combiner` und `keys` des **letzten** Builds
    über dasselbe Memo.
  - Das Memo hält die kombinierten **Daten** fest, nicht das
    `CombinedResult`. Jedes `combine` baut ein neues `CombinedResult`, und
    verglichen wird mit `==`. (Die erste Fassung sprach von „derselben
    Instanz“. Das war falsch.)
- **`keys` ist Pflicht (Fable P3-9).**
  - In React läuft ein inline `combine` bei jedem Rendern neu. Hier läuft
    der Combiner nur neu, wenn sich ein Wert oder ein Schlüssel geändert hat.
  - Ein Combiner, der Zustand aus dem Build einfängt, lieferte ohne `keys`
    still ein veraltetes Ergebnis.
  - `const []` sagt „fängt nichts ein“, so wie bei `useMemoized`.
- **Portierung:**
  - 871 wird voll portiert (zwei Renderings).
  - 490 wird teilweise portiert (Lückentabelle). `buildWhen: (p, c) =>
    p.dataOrNull != c.dataOrNull` hält die Invariante am Ende.
  - 1142 läuft über das schlichte `useQueries`: Sein Identitäts-Combiner
    über rohe Ergebnisse *ist* `useQueries`, und die Länge pro Build wird
    geprüft wie upstream (Astra H-05).
- **Ausgelassen:** 817 verlangt einen rohen Combiner, der `'foo'` schon im
  ersten Rendering liefert. Nach #82 nicht im Umfang.
- **Backlog HB-2:** Dieselbe Regel für `QueriesBuilder` und
  `QueriesController`.
  - Die Hooks dürfen sie zuerst haben, weil sie kein fünfter Aufrufstil
    sind (D15). Die Gleichrangigkeit gilt für die vier Stile der Bindung.
  - Die Bindung übernimmt die Regel für alle vier zugleich, sobald sie sich
    bewährt hat.

### D11 — `usePrefetchQuery`, `usePrefetchInfiniteQuery`

- **Antwort:** Wie upstream.
  - Im `build` wird geprüft, ob der Schlüssel einen Cache-Eintrag hat:
    **`client.queryCache.find(filters: QueryFilters(queryKey: key, exact:
    true)) == null`**.
  - Fehlt er, wird `client.query(options).ignore()` aufgerufen,
    beziehungsweise `client.infiniteQuery(…)`.
  - Die Hooks geben nichts zurück, bauen nie neu und halten keinen
    Observer.
- **Nicht `getQueryState(key) == null` (Fable P2-1).**
  - Upstreams `getQueryState` ist untypisiert, unseres nicht. Ohne
    Typargument fragt es nach einem `dynamic`-Eintrag. Den gibt es nie.
    Darum wirft es `QueryDataTypeError`, sobald der Eintrag existiert, also
    beim zweiten Build.
  - Gemessen: Der Spike reproduziert den Wurf, und `find` wirft nicht
    (Messung 10).
- **Warum:**
  - Der Sinn ist „fetch-then-render“: Ein Elternwidget startet den Abruf,
    bevor das Kind, das die Daten liest, gebaut wird. Upstream braucht dafür
    Suspense, hier reicht die Reihenfolge der Builds.
  - Bei jedem Build ist das günstig: ein Nachschlagen in einer Map.
  - **Der Prefetch-Hook selbst** ruft einen fehlgeschlagenen oder
    laufenden Eintrag nicht erneut ab. Das ist upstreams ausdrückliche
    Zusage. Ein lesender Hook kann denselben Eintrag unabhängig davon neu
    abrufen.
- **Benachrichtigungen:** Ein Abruf, der im `build` startet, benachrichtigt
  den Cache.
  - Mit Provider wird die Zustellung bis nach dem Frame zurückgestellt.
  - Ohne Provider ist sie eine Microtask (D7).
  - AP8 prüft beides mit einem `useIsFetching` im selben Baum.

### D12 — `useIsFetching` und `useIsMutating` lesen den Client

- **Optionen:**
  - (a) `IsFetchingController` je Hook, neu gebaut, wenn sich die Filter
    ändern.
  - (b) Direkt `client.queryCache.subscribe` beziehungsweise
    `mutationCache.subscribe`. Gezählt wird mit
    `client.isFetching(filters: …)` und den Filtern des letzten Builds.
- **Antwort:** (b).
- **Warum:**
  - `QueryFilters` und `MutationFilters` haben kein `==`. (a) würde bei
    jedem Build mit einem neuen Filter-Objekt einen neuen Controller bauen.
    `IsFetchingController` hat keinen Setter. Seine Filter sind „fixed for
    the controller's life“.
  - (b) ist upstreams Form: `useSyncExternalStore` über
    `client.isFetching(filters)`.
  - `MutationStateController` dagegen *hat* `setOptions`. Darum geht
    `useMutationState` über ihn (D9).
- **Takt:** Der Listener übergibt an `client.notifyManager.schedule` und
  baut nur neu, wenn sich die Zahl geändert hat. Es gilt also dieselbe
  Taktung wie bei den Controllern.
- **Schutz vor späten Zustellungen (Astra H-03):**
  - Jedes Abo trägt eine Generation. Ein Wechsel des Clients und `dispose`
    erhöhen sie, `dispose` setzt außerdem ein Disposed-Flag.
  - Die eingereihte Zustellung prüft beides, bevor sie Filter liest oder
    `setState` ruft.
  - Ein Umzug per `GlobalKey` behält das Abo.
  - Gemessen: Ohne den Schutz baut eine Zustellung, die vor dem Entsorgen
    eingereiht war, das Element neu (Messung 8).
- **Fall 60** („should not update state while rendering“) prüft genau den
  Fall, den der Provider zurückstellt. Er ist im Spike grün.
- **Backlog HB-3:** Ein `IsMutatingController` für die übrigen
  Aufrufstile, falls er gebraucht wird.

### D13 — Ein Wurf im Build: abweichendes Verhalten, dokumentiert

- **Befund:** Wirft der Build eines `HookWidget`, entsorgt `flutter_hooks`
  Hooks ab dem Cursor (Ausgangslage). Unsere Builder behalten dagegen ihren
  State und erholen sich (Bindung 1.0.4).
- **Antwort:** Nicht umgehen. Das liegt in `flutter_hooks` und ist dort
  Absicht. Die Doku nennt die Folgen unten, und Tests halten jede fest.
- **Folgen, getrennt nach dem, was überlebt** (Astra H-04, im Spike
  gemessen, Messung 9):

  | Was | Ein Wurf vor dem Hook |
  |---|---|
  | Cache-Eintrag einer Query | Bleibt `gcTime` lang. Bei `gcTime: 0` ist er weg, wenn der letzte Observer geht |
  | Laufender Abruf einer Query | Hat der Query-Funktion das Signal benutzt, wird er abgebrochen und zurückgesetzt, sobald der letzte Observer geht. Sonst läuft er weiter. Der nächste Build ruft neu ab |
  | Laufende Mutation | Läuft weiter. Ihre Options-Callbacks laufen |
  | Per-Call-Callbacks von `mutate` | Fallen weg: Der Controller ist entsorgt |
  | Was der Hook zeigt | Der Ersatz-Hook beginnt neu. Bei einer Mutation ist er `idle`, auch wenn die alte noch läuft. Er findet sie nicht über den Schlüssel wieder |
  | Am Observer gemerkt | `placeholderData` mit vorherigen Daten und das `select`-Memo sind weg |

- **Genau:** Entsorgt werden nur Hooks ab der Wurfstelle. Ein Wurf nach dem
  letzten Hook entsorgt nichts, und der Spike-Test dazu ist grün.
- **Empfehlung in der Doku:** Code, der werfen kann, gehört hinter die
  Hooks oder in ein eigenes Widget.

### D14 — Was nicht kommt

| Upstream | Warum nicht |
|---|---|
| `useSuspenseQuery`, `useSuspenseQueries`, `useSuspenseInfiniteQuery`, Suspense in `usePrefetch*` | Flutter hat kein Suspense. Ein Ersatz wäre ein eigenes Produkt |
| `QueryErrorResetBoundary`, `throwOnError` | #15: Fehler sind Daten im Ergebnis |
| `HydrationBoundary`, `IsRestoringProvider` | Kein Persister und keine Hydration im Kern (#15) |
| `subscribed` | Backlog HB-1, für alle Aufrufstile zugleich |
| `skipToken` | `Enabled.no` und eine bedingte Option decken das ab |
| `retryOnMount` als Callback | Die Kernoption ist `bool?`. Ein Callback wäre eine Kernänderung ohne Befund |
| Rohes `combine` | #82 |
| Callback-Kontext für Mutationen | Divergenz #14/#83 |
| `queryOptions`/`mutationOptions` als Hooks | In Dart sind das Funktionen, die Options zurückgeben. Die portierbaren Fälle aus `mutationOptions.test.tsx` laufen gegen die Hooks |

### D15 — Hooks sind kein fünfter Aufrufstil

- **Optionen:**
  - (a) Hooks werden der fünfte gleichrangige Aufrufstil, mit Spalte in
    `catalogue_test.dart` und Bildschirm im Showcase.
  - (b) Hooks sind ein eigenes Zusatzpaket mit eigener Doku-Seite, eigener
    Beispiel-App und eigener Suite.
- **Antwort:** (b).
- **Warum:**
  - Die Gleichrangigkeit der vier Stile ist eine Zusage der Bindung (C49),
    nachgewiesen in der Bindung und im Showcase.
  - Ein Zusatzpaket mit Drittabhängigkeit gehört nicht in diesen Nachweis.
    Der Showcase dürfte es nach #21 nicht einmal als Abhängigkeit haben.
  - Christians zweite Regel aus #21, keine Voreinstellung in der Doku,
    bleibt: Die Hooks-Seite empfiehlt Hooks nicht über die vier Stile.
- **Doku:**
  - Eine Seite `guides/hooks.md`.
  - Eine Spalte „mit `query_kit_hooks`“ in `coming-from-react-query.md`.
    Wer von React kommt, sucht genau das.
  - Eine Zeile auf `installation.md`.
  - Der Abschnitt „Signals, hooks…“ wird neu geschrieben: Hooks gibt es als
    Zusatzpaket, für Signals gilt weiter das Bisherige.
- **Wo die Doku-Beispiele kompiliert werden (Fable P3-5):**
  - Optionen:
    - (i) `examples/doc_snippets` bekommt `query_kit_hooks` als
      Abhängigkeit.
    - (ii) Ein Zwilling von `site_fences_test.dart` im Hook-Paket liest
      `website/docs/guides/hooks.md` und die README des Pakets.
  - Antwort: (ii).
  - (i) holte `flutter_hooks` transitiv in ein Beispiel. Das bräche die
    Regel aus #21, die laut CLAUDE.md für alles darauf Gebaute gilt.
  - (ii) braucht AP9 ohnehin für die README, und `_readmes` in
    `doc_snippets` bleibt bei zwei Paketen.
  - ADR-0004 hält das fest.

### D16 — Tests: wie im Kern

- **Eigene `test/PORTING_NOTES.md`.**
  - Eine Dart-Datei pro Upstream-Datei, die Upstream-Namen bleiben.
  - Jede Auslassung und jede geänderte Assertion steht mit Grund darin.
  - Paketeigenes Verhalten steht in `hook_specifics_test.dart`.
  - Reproduktionen von Review-Befunden stehen in eigenen Dateien je Runde,
    so wie `review_reproductions_test.dart` im Spike.
- **Harness `test/harness.dart`**, wie im Spike:
  - `hookTest` wickelt ein: Client, Provider und den Teardown aus ADR-0002.
  - `HookProbe` ist `flutter_hooks`' `HookBuilder` (Fable P3-6). Es wird
    nicht nachgebaut. Der Harness fügt nur den Recorder hinzu: jeden Build
    (`states`, upstreams `states.push`) und, getrennt davon, die Übergänge
    am Observer (D8).
  - `advance(ms)` pumpt gestaffelt, eine Millisekunde pro Frame (D8).
    `click` ist Tap plus `pump`.
  - Fehler, die in der Zone landen, fängt `runZonedGuarded`.
- **Keine Abhängigkeit auf `flutter_hooks_test`:** Es wird von der
  Community gepflegt, und der Harness braucht nur `pumpWidget`.
- **Upstream geht vor:** Scheitert ein portierter Fall, liegt der Fehler
  zuerst im Hook. Nur eine Entscheidung dieses Plans (D8 Takt, D10, D14)
  rechtfertigt eine geänderte Assertion.

### D17 — Version und Release

- **Antwort:**
  - 0.1.0, wenn AP3 bis AP11 abgeschlossen sind.
  - **`query_kit_flutter` 1.1.0 erscheint am selben Tag** (Fable P2-4).
    `adapter.dart` liegt bis dahin unveröffentlicht auf `main`. AP3 bis
    AP11 laufen über den Pfad im Workspace dagegen, und die Reviews aus
    AP11 lesen die exportierte Fläche, bevor sie unter SemVer fällt.
  - 1.0.0, wenn eine echte App das Paket benutzt hat und ein Review über
    ihre Befunde gelaufen ist. Das ist der Weg, den der Kern mit BR64
    gegangen ist.
  - Tag `query_kit_hooks-v*`.
  - Das erste Publish macht Christian von Hand, weil pub.dev das
    automatisierte Publish erst für ein existierendes Paket erlaubt
    (`docs/releasing.md`). Danach „Transfer to publisher“ an dualmeta.io und
    die Einstellung für automatisches Publish.
- **Warum 0.x:**
  - Die Hook-API hat noch keine Nutzer.
  - Sie hängt an einem Paket vor 1.0.
  - In 0.x ist ein Bruch ein Minor-Sprung (0.1 → 0.2). Die Regel der
    beiden 1.x-Pakete, ein Bruch sei eine Major-Version, gilt hier erst ab
    1.0.0.

### D18 — Beispiel: eine eigene App, kein Showcase-Bildschirm

- **Antwort:**
  - `packages/query_kit_hooks/example/` liegt außerhalb des Workspace und
    wird mit veröffentlicht, wie das Beispiel der Bindung.
  - Es ist ein kleiner Bildschirm mit Liste und Detail. Er deckt `useQuery`,
    `useMutation` mit optimistischem Update, `useInfiniteQuery` und
    `usePrefetchQuery` ab.
  - Dazu kommt ein Widget-Test gegen einen Fake.
- **Warum:** D15. Der Showcase darf `flutter_hooks` nicht einbinden, und
  ein Beispiel im Paket ist das, was pub.dev zeigt.

---

## Arbeitspakete

Jedes Paket wird ein Ticket der neuen Wayfinder-Map. Die Map wird erst
angelegt, wenn Christian den Plan freigegeben hat, weil das nach außen
sichtbar ist. Die Gates gelten für jedes Paket in demselben Commit: Tests,
Analyzer, Formatter und `PORTING_NOTES`-Eintrag.

### AP0 — Spike (POC) — **erledigt, Ergebnis: weiter**

- **Ort:** `packages/query_kit_hooks/`, nicht im Workspace.
  - Pfad-Abhängigkeiten über `pubspec_overrides.yaml` (`../query_kit`,
    `../query_kit_flutter`).
  - Keine Änderung an der Root-`pubspec.yaml`, kein Commit, bis AP2 das
    Paket aufnimmt.
- **Gebaut**, nur auf öffentlicher API (D4, Pfad A):
  - `useQuery`, `useSelectQuery`, `useInfiniteQuery` und `useMutation`
  - `useQueries` und `useCombinedQueries`
  - `useIsFetching`, `useIsMutating` und `useMutationState`
  - `usePrefetchQuery`
  - der Harness aus D16
- **Portiert, 31 Fälle:**
  - useQuery: 72, 435, 700, 738, 1128, 1185, 1606, 1932, 1956, 2300, 2316,
    3763, 3871, 4100, 4447, 4622, 5056, 6068, 6191, 6378, 6570
  - useInfiniteQuery: 48, 180
  - useQueries: 490 (teilweise), 871, 1142
  - useMutation: 34, 999, 1578
  - useIsFetching: 60
  - useMutationState: 17
- **Dazu:** 8 eigene Fälle und 6 Reproduktionen von Review-Befunden, zwei
  davon mit Gegenprobe.
- **Ergebnis:** 45 von 45 grün, gegen den committeten Stand (Bindung
  1.0.3) und, bis auf den zuletzt geschriebenen Fall, gegen den
  Arbeitsstand 1.0.4. Messungen und Bericht in
  [`docs/research/hooks-spike.md`](../research/hooks-spike.md).
- **Das Gate, nach den Reviews neu gefasst** (Astra H-02, Fable P3-4). Die
  erste Fassung ließ bis zu 20 % rote Fälle zu und zählte geänderte
  Assertionen statt geänderter Builds.
  - **Jede Verhaltens-Invariante ist grün.** Das ist eine Bedingung, keine
    Quote.
  - Der Anteil angepasster Assertionen ist eine **Messung**, keine Schwelle:
    3 von 31 (738, 6068, 490).
  - Gezählt wird, ob sich **Zahl oder Reihenfolge der Builds** ändern: 1 von
    31 (490, durch D10).
  - 4447 zählt nicht mit. Ein doppeltes `select` wäre eine Eigenschaft von
    Kern und Bindung, kein Urteil über den Spike. Es lief ohnehin nicht
    doppelt.
  - Kein Hook braucht verborgene API.
  - Kein Timer und keine Build-Assertion bleibt übrig.
  - Geprüft sind außerdem:
    - Client-Wechsel, Umzug per `GlobalKey`, Hot Reload, Unmount
    - späte Zustellung nach dem Entsorgen
    - Erholung nach einem Wurf vor, zwischen und nach Hooks

### AP1 — `RebuildRule` in `query_kit_flutter` (`adapter.dart`) — **erledigt** (#94)

- **Inhalt:**
  - Die neue Bibliothek `lib/adapter.dart` exportiert `RebuildRule<T>`, in
    der Form des Spikes: Closures für Wert und beobachteten Zustand,
    `read()` und `shouldRebuild(buildWhen)`.
  - `ReadEntry` behält Abo und Besitz und delegiert die Entscheidung an
    `RebuildRule`. Damit gibt es eine Regel, nicht zwei.
  - Eine Dartdoc, die sagt, für wen die Bibliothek ist.
  - ADR-0004 „Hooks als Zusatzpaket über eine Adapter-Bibliothek“, mit D4
    und D15.
  - CHANGELOG-Eintrag unter „Unreleased“. Die Version wird erst in AP12
    gesetzt (D17).
- **Akzeptanz:**
  - Die Barrel-Datei bleibt unverändert, und alle Tests der Bindung bleiben
    grün: 299 auf diesem Zweig (`859fbdc`, Bindung 1.0.3), 349 mit der
    1.0.4-Arbeit aus dem Haupt-Checkout.
  - Ein neuer Test importiert nur `adapter.dart`. Er prüft die drei Zweige
    der Regel: gleich, nur die Nebenhälfte bewegt, `buildWhen`.
  - `dart doc` und die Probeläufe fürs Publish sind grün. pana bleibt bei
    160/160.

### AP2 — Paket-Gerüst und Integration ins Repo

- **Inhalt:** Das Paket kommt in den Workspace, mit `pubspec`, `LICENSE`,
  `LICENSE-TANSTACK`, `README`, `CHANGELOG`, `analysis_options` und
  `dartdoc_options`. Dazu die Stellen, die heute nur zwei Pakete kennen:
  - `tool/rename_packages.dart` (Z. 172–175)
  - `.gitignore` (Z. 10 und 14, `pubspec_overrides` des Beispiels)
  - `publish.yml` (Z. 19–20, 31–35)
  - `scripts/release.sh` (Z. 194–197, kennt nur zwei Pakete)
  - `ci.yml`: Gates, `floors` (mit `flutter_hooks` 0.21.2, D3) und
    `latest-stable.yml`
  - `dependabot`, die PR-Vorlage, `docs/releasing.md`, `CLAUDE.md`
- **Akzeptanz:** CI ist grün über alle Jobs mit drei Paketen, und die
  Probeläufe fürs Publish laufen für alle drei.

### AP3 — `useQuery`, `useSelectQuery` und die Portierung von `useQuery.test.tsx`

- **Inhalt:** Die Hooks auf `RebuildRule` aus `adapter.dart` (D4). Die
  Suite wird in zwei Dateien portiert, entlang der Teilung der Inventur bei
  Zeile 3600.
- **Akzeptanz:**
  - Jeder Fall ist portiert oder mit Grund ausgelassen.
  - Die Folgen aus D13 sind als Tests festgehalten: Wurf im Hook, zwischen
    Hooks und nach dem letzten Hook, mit einem Abruf, der das Signal
    benutzt.
  - Die Spike-Fälle laufen gegen die endgültigen Hooks.

### AP4 — `useInfiniteQuery`

- **Inhalt:** Die 28 Fälle, davon 22 angepasst. Die Tests zeichnen die
  Paging-Flags je Build vom Controller auf, wie 48 und 180 im Spike.

### AP5 — `useMutation`

- **Inhalt:** 61 Fälle aus `useMutation.test.tsx` und 14 aus
  `mutationOptions.test.tsx`.
- **Akzeptanz:**
  - 2533 und 2555 sind als Divergenz #14/#83 eingetragen.
  - Ein Test belegt, dass `dispose` eine laufende Mutation nicht abbricht.
  - Ein Test belegt die Mutations-Zeilen aus D13: Die Per-Call-Callbacks
    fallen weg, und der Ersatz-Hook beginnt `idle`.

### AP6 — `useQueries` und `useCombinedQueries`

- **Inhalt:**
  - Die 24 Fälle.
  - 871 läuft über `useCombinedQueries`, 490 teilweise (D10).
  - 1142 läuft über `useQueries`, mit der Länge je Build.
  - 817 ist als Auslassung nach #82 eingetragen.
- **Akzeptanz:**
  - Eine Query, deren Änderung das kombinierte Ergebnis nicht bewegt, löst
    keinen Build aus.
  - Eine Änderung nur dessen, worauf `retry` wirkt, löst einen aus (H-01,
    aus dem Spike übernommen).

### AP7 — `useIsFetching`, `useIsMutating`, `useMutationState`, `useQueryClient`

- **Inhalt:** Die Dateien `useIsFetching.test.tsx` (5),
  `useMutationState.test.tsx` (5) und `QueryClientProvider.test.tsx` (4).
- **Akzeptanz:**
  - Filter und `select`, die bei jedem Build neu sind, erzeugen weder ein
    neues Abo noch einen zusätzlichen Build.
  - Eine Zustellung, die vor dem Entsorgen des Hooks eingereiht war, und
    eine für den alten Client nach einem Client-Wechsel bewirken nichts
    (H-03).

### AP8 — `usePrefetchQuery`, `usePrefetchInfiniteQuery`

- **Inhalt:** Die vier anpassbaren der neun Prefetch-Fälle, dazu ein Test
  mit `useIsFetching` im selben Baum, mit und ohne Provider (D11).
- **Akzeptanz:**
  - Ein Build mit vorhandenem Eintrag wirft nicht (P2-1).
  - Der Prefetch-Hook ruft einen fehlgeschlagenen Eintrag nicht erneut ab.
  - Keine Assertion „setState during build“.

### AP9 — Doku

- **Inhalt:**
  - Das, was D15 aufzählt.
  - Die README des Pakets.
  - Der Fence-Test im Hook-Paket über README und `guides/hooks.md` (D15).
  - Ein Eintrag in den Unterschieden zu TanStack.
  - Die Folgen aus D13 auf der Hooks-Seite.
- **Akzeptanz:** Der Site-Build, die Fences beider Orte und `doc_snippets`
  sind grün.

### AP10 — Beispiel-App

- **Inhalt:** Wie D18 beschreibt.
- **Akzeptanz:** Das Beispiel lebt im veröffentlichten Archiv und läuft dort
  mit `flutter test`.

### AP11 — Review-Runde

- **Inhalt:**
  - Zwei unabhängige Reviews mit verschiedenen Modellen, jedes in einem
    eigenen Worktree, gegen upstream, gegen diesen Plan und gegen die
    Fläche von `adapter.dart`.
  - Jeder Befund wird erst reproduziert, dann bearbeitet.
  - Danach frische Verifikationsdurchgänge über die Fixes, bis ein Durchgang
    keinen neuen Fehler findet.
- **Akzeptanz:** Die `PORTING_NOTES` haben einen Abschnitt je Durchgang.

### AP12 — Release: `query_kit_hooks` 0.1.0 und `query_kit_flutter` 1.1.0

- **Inhalt:**
  - Beide Versionen setzen und beide Tags am selben Commit:
    `query_kit_flutter-v1.1.0` und `query_kit_hooks-v0.1.0`.
  - Die Bindung veröffentlicht `publish.yml` wie gewohnt.
  - Das Hook-Paket veröffentlicht Christian zum ersten Mal von Hand, mit
    der Bindung 1.1.0 schon auf pub.dev. Danach Transfer an den Publisher
    und die Einstellung für automatisches Publish.
  - Vorher wird der Name auf pub.dev noch einmal geprüft (D2).

**Reihenfolge:**

- AP0 und AP1 sind erledigt.
- Danach AP1 und AP2.
- Danach AP3. Die übrigen Hooks bauen auf seinem Muster auf.
- AP4 bis AP8 sind voneinander unabhängig.
- AP9 und AP10, sobald die Hooks stehen.
- Dann AP11, dann AP12.

---

## Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| `flutter_hooks` vor 1.0. Die Abkopplung von `material` (#491) kann es brechen, und ein 0.22 fällt aus `^0.21.2` heraus | Das Paket läuft in `latest-stable.yml` mit. Dependabot meldet neue Versionen. Die Hooks nutzen nur `Hook`, `HookState`, `use` und `useContext`, wenig Fläche |
| `^0.21.2` löst je nach Flutter zwei Versionen auf (D3) | `floors` und Stable laufen beide. Keine Lockdatei legt den `floors`-Job fest |
| Takt der Frames: Upstream rendert nach jedem Timer-Makrotask | Gestaffeltes Pumpen. Im Spike reichte das für 31 von 31 Fällen, die einzige geänderte Zählung ist durch D10 gewollt |
| `adapter.dart` macht eine interne Regel öffentlich | Eine besitzfreie Klasse (D4). Erst nach AP11 veröffentlicht (D17). Dartdoc und ADR-0004. Eine Änderung daran ist eine Major-Version der Bindung |
| Abweichung bei einem Wurf im Build (D13) | Folgen einzeln dokumentiert und als Tests festgehalten |
| Späte Zustellung an einen entsorgten Hook-State (D5, D12) | Generation und Disposed-Flag bei direkten Abos, Listener und `ControllerLifetime` bei Controllern. Tests mit Gegenprobe |
| Ein Combiner ohne passende `keys` liefert ein veraltetes Ergebnis (D10) | `keys` ist Pflicht und in der Dartdoc des Hooks erklärt |
| Umfang: etwa 260 Fälle | Die Pakete AP4 bis AP8 lassen sich parallel bearbeiten. Die Fälle mit P zuerst, die mit A danach |

## Offene Punkte

Werden im genannten Paket entschieden und dort begründet:

- **Ob `useInfiniteQuery` die Paging-Flags in `buildWhen` sieht.** Bisher
  folgt es `context.infiniteQuery`: `buildWhen` sieht das Ergebnis, und
  eine Bewegung nur der Flags baut immer neu. Entschieden in AP4.
- **Die echten Fallzahlen.** Die Inventur ordnet ein, die Portierung zählt.
  Die `PORTING_NOTES` sind die Zahl, die gilt.

---

## Review-Protokoll

Zwei unabhängige Reviews des ersten Entwurfs, beide nur lesend, mit
demselben Auftrag:

- Astra (GPT-6-Astra über die Codex CLI)
- Fable (Fable 5.1)

**Kein Befund wurde übernommen, ohne ihn am Code zu prüfen.** Wo möglich,
wurde er im Spike als Test reproduziert, bei zwei Befunden mit Gegenprobe:
Der Test scheitert, wenn man die Maßnahme herausnimmt.

| Befund | Quelle | Geprüft | Wie | Ergebnis |
|---|---|---|---|---|
| Combine-Gate behält veraltetes `retry` | Astra H-01 (P1) | **reproduziert** | Spike-Test mit Gegenprobe (Messung 7) | D10: Aktionsschlüssel im Gate. Aussage „dieselbe Instanz“ korrigiert |
| Spike kann sein Gate nicht begründen; 80 %-Schwelle; D8-Prämisse | Astra H-02 (P1) | bestätigt | Gelesen; 2316 zeigt Bündelung | AP0 erweitert (Infinite, Liste, Kombination, Zähler, Prefetch, Lebenszyklus). Gate neu gefasst. D8 korrigiert. Observer-Übergänge getrennt aufgezeichnet |
| `context.mounted` belegt nicht, dass der Hook lebt | Astra H-03 | **reproduziert** | Spike-Test mit Gegenprobe (Messung 8) | D5 Regel 5, D12: Generation und Disposed-Flag |
| Folgen eines Wurfs untertrieben | Astra H-04 | **reproduziert** | Zwei Spike-Tests (Messung 9) | D13 als Tabelle der Folgen. AP3 und AP5 prüfen sie |
| 490 und 1142 behalten ihre Assertionen nicht | Astra H-05 | bestätigt | `_combine` gelesen; im Spike portiert | 490 teilweise, 1142 über `useQueries` |
| `ReadEntry` zu exportieren veröffentlicht einen unsoliden Besitzvertrag | Astra H-06 | bestätigt | `read_entry.dart` gelesen: Cast und Entsorgen | D4: (B′), besitzfreie `RebuildRule` |
| Backlog widerspricht sich; falsche Verweise | Astra H-07, Fable P3-2 | bestätigt | Zeilen nachgezählt | Backlog korrigiert: Einleitung, HB-1 (5921–6031, useQueries 66), HB-2 (D10) |
| `getQueryState` ohne Typargument wirft | Fable P2-1 | **reproduziert** | Spike-Test (Messung 10) | D11: `queryCache.find(…exact)`. AP8-Akzeptanz |
| `useMutationState` kann nicht über `MutationStateController` gehen | Fable P2-2 | **nicht reproduziert** | Der Controller hat `setOptions({filters, select})`. Spike-Test: neue Filter je Build, kein Abo, kein Build (Messung 11) | D9 unverändert, Begründung ergänzt |
| AP0 misst die Fläche mit den trivialen Hooks | Fable P2-3 | bestätigt | Gelesen | Spike um Infinite, Liste und Kombination erweitert. Fläche gemessen: nur `RebuildRule` |
| Bindung 1.1.0 vor dem ersten Nutzer veröffentlicht | Fable P2-4 | bestätigt | Reihenfolge der APs | D17, AP1, AP12: 1.1.0 erscheint mit dem Hook-Paket |
| Risiko ohne Provider übertrieben | Fable P3-1, Astra (geprüft-Liste) | bestätigt | `notify_manager.dart:76` | D7 und D11 neu gefasst |
| `^0.21.2` löst zwei Versionen auf | Fable P3-3 | bestätigt | Beide `pubspec.yaml` gelesen | D3, Ausgangslage, Risiken |
| Gate zählt das Falsche; 4447 gehört nicht in die Quote | Fable P3-4 | bestätigt | — | AP0-Gate |
| `doc_snippets` bräche #21 still | Fable P3-5 | bestätigt | `examples/doc_snippets/pubspec.yaml` | D15: Fence-Test im Hook-Paket |
| `HookProbe` gibt es als `HookBuilder` | Fable P3-6 | bestätigt | `framework.dart:627` | D16 |
| Wurf in einem Hook entsorgt diesen Hook mit; `use()` im `build` entsorgt vor dem Wurf | Fable P3-7, Astra H-04 | bestätigt | `framework.dart` 430–492 gelesen | Ausgangslage, D5 Regel 8, D13 |
| Benachrichtigung bei inaktivem Element verworfen | Fable P3-8 (i) | **nicht erreichbar** | Inaktiv nur innerhalb der Build-Phase. Zustellungen dort nie synchron. Spike-Test zum `GlobalKey`-Umzug grün | D5, als geteilt und nicht erreichbar notiert |
| `dispose` nach `super.unmount` | Fable P3-8 (ii) | bestätigt | `framework.dart` 508–520 | D5 Regel 6 |
| `keys:`-Falle trifft React-Gewohnheiten | Fable P3-9 | bestätigt | `combined_result.dart` 225–229 | D10: `keys` Pflicht |
| Issue-Nummern, Release-Datum, Namen auf pub.dev | Fable P3-10 | offline nicht geprüft | — | Bleibt aus der Recherche. Der Name wird vor AP12 erneut geprüft (D2) |
| Identische Hook-Instanzen überspringen `didUpdateHook` | Astra (geprüft-Liste) | bestätigt | Upstream-Test von `flutter_hooks` | Ausgangslage. Die Hooks sind nie identisch, weil jeder Build sie mit neuen Optionen erzeugt |

Beide Reviews fanden die übrigen Behauptungen richtig: den Lebenszyklus von
`flutter_hooks`, die API der Bindung, die Inventur und die Verweise ins
Repo.
