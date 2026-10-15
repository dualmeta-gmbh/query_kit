/// The Todos tab: a list that is written to, optimistically, in both of
/// React Query's ways.
library;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'app.dart';
import 'group.dart';
import 'queries.dart';

class TodosTab extends HookWidget {
  const TodosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    final client = useQueryClient();
    final todos = useQuery(todosQuery(api));
    final open = useSelectQuery(openTodosQuery(api));
    final toggle = useMutation(toggleTodoMutation(client, api));
    final add = useMutation(addTodoMutation(client, api));
    // What every pending add was called with: the rows the list shows until
    // the backend has them.
    final adding = useTypedMutationState(
      filters: MutationFilters(
        mutationKey: Keys.addTodo,
        status: MutationStatus.pending,
      ),
      select: (Mutation<Object?, String, Object?> mutation) =>
          mutation.state.variables!,
    );
    final text = useTextEditingController();

    void submit() {
      final value = text.text.trim();
      if (value.isEmpty) {
        return;
      }
      add.mutate(value);
      text.clear();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Group(
          name: 'open todos',
          child: Text(
            switch (open) {
              QuerySuccess(:final data) => '$data open',
              _ => '… open',
            },
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: text,
                decoration: const InputDecoration(labelText: 'New todo'),
                onSubmitted: (_) => submit(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: submit, child: const Text('Add')),
          ],
        ),
        const SizedBox(height: 8),
        switch (todos) {
          QueryPending() => const Text('Loading todos…'),
          QueryError(:final error) => Text('$error'),
          QuerySuccess(:final data) => Group(
              name: 'todos',
              child: Column(
                children: [
                  for (final todo in data)
                    CheckboxListTile(
                      value: todo.done,
                      title: Text(todo.text),
                      onChanged: (done) =>
                          toggle.mutate((id: todo.id, done: done ?? false)),
                    ),
                  // A row, not a `ListTile`: nothing here can be tapped, and
                  // a tile's selected state would make it a labelled node on
                  // the web instead of the text it is.
                  for (final pending in adding)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 16),
                          Text('Adding: $pending'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        },
      ],
    );
  }
}
