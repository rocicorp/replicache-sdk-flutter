class Todo {
  String id;
  String title;
  bool done;
  num order;

  Todo(this.id, this.title, this.done, this.order);

  factory Todo.fromJson(String id, Map<String, dynamic> data) =>
      Todo(id, data['title'], data['done'], data['order']);

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'done': done,
      'order': order,
    };
  }
}
