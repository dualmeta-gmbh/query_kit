// Ported from query/packages/react-query/src/__tests__/useIsFetching.test.tsx
// at 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useIsFetching.test.tsx:60
  hookTest('should not update state while rendering', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final isFetchingArray = <int>[];

    // Functions, not instances: React re-renders a child element created
    // anew in the parent's render, and Flutter does so for a new widget.
    Widget isFetching() => HookBuilder(builder: (context) {
          isFetchingArray.add(useIsFetching());
          return const SizedBox();
        });
    Widget firstQuery() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => sleep(100).then((_) => 'data1'),
          ));
          return const SizedBox();
        });
    Widget secondQuery() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => sleep(100).then((_) => 'data2'),
          ));
          return const SizedBox();
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final renderSecond = useState(false);
        useEffect(() {
          final timer = Timer(
            const Duration(milliseconds: 50),
            () => renderSecond.value = true,
          );
          return timer.cancel;
        }, const []);
        return Column(children: [
          isFetching(),
          firstQuery(),
          if (renderSecond.value) secondQuery(),
        ]);
      }),
    );

    expect(isFetchingArray[0], 0);
    await advance(tester, 0);
    expect(isFetchingArray[1], 1);
    await advance(tester, 50);
    expect(isFetchingArray[2], 1);
    await advance(tester, 1);
    expect(isFetchingArray[3], 2);
    await advance(tester, 50);
    expect(isFetchingArray[4], 1);
    await advance(tester, 50);
    expect(isFetchingArray[5], 0);
  });
}
