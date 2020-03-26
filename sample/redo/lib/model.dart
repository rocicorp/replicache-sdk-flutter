class Todo {
  String id;
  String text;
  bool complete;
  num order;

  Todo(this.id, this.text, this.complete, this.order);

  factory Todo.fromJson(String id, Map<String, dynamic> data) =>
      Todo(id, data['text'], data['complete'], data['order']);

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'complete': complete,
      'order': order,
    };
  }
}
