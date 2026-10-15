import 'package:flutter/widgets.dart';

/// A named semantics group: one node whose children stay nodes of their own.
///
/// It is how the tests find a part of a screen. [name] is the group's
/// semantics label, which the Playwright suite reads with
/// `getByRole('group', { name })`, and its widget key, which the widget and
/// native tests read with `find.byKey`. A screen reader hears the same name.
class Group extends StatelessWidget {
  const Group({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        key: ValueKey<String>(name),
        container: true,
        explicitChildNodes: true,
        label: name,
        child: child,
      );
}
