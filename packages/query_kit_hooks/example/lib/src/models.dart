/// The wire types, typed by hand: the client's copy of
/// `examples/showcase/server/types.ts`, for the routes this app calls.
library;

class Post {
  const Post({required this.id, required this.title, required this.body});

  factory Post.fromJson(Map<String, Object?> json) => Post(
        id: json['id']! as int,
        title: json['title']! as String,
        body: json['body']! as String,
      );

  final int id;
  final String title;
  final String body;
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.text,
  });

  factory Comment.fromJson(Map<String, Object?> json) => Comment(
        id: json['id']! as int,
        postId: json['postId']! as int,
        author: json['author']! as String,
        text: json['text']! as String,
      );

  final int id;
  final int postId;
  final String author;
  final String text;
}

class Todo {
  const Todo({required this.id, required this.text, required this.done});

  factory Todo.fromJson(Map<String, Object?> json) => Todo(
        id: json['id']! as int,
        text: json['text']! as String,
        done: json['done']! as bool,
      );

  final int id;
  final String text;
  final bool done;

  Todo copyWith({bool? done}) =>
      Todo(id: id, text: text, done: done ?? this.done);

  @override
  bool operator ==(Object other) =>
      other is Todo &&
      other.id == id &&
      other.text == text &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, text, done);
}

class Project {
  const Project({required this.id, required this.name});

  factory Project.fromJson(Map<String, Object?> json) => Project(
        id: json['id']! as int,
        name: json['name']! as String,
      );

  final int id;
  final String name;
}

/// One page of projects, fetched from a cursor: the items and where the next
/// page starts, `null` after the last.
class ProjectSlice {
  const ProjectSlice({required this.items, required this.nextId});

  factory ProjectSlice.fromJson(Map<String, Object?> json) => ProjectSlice(
        items: (json['items']! as List<Object?>)
            .map((item) => Project.fromJson(item! as Map<String, Object?>))
            .toList(),
        nextId: json['nextId'] as int?,
      );

  final List<Project> items;
  final int? nextId;
}
