class Todo {
  String id;
  num listId;
  String text;
  bool complete;
  num order;

  Todo(this.id, this.listId, this.text, this.complete, this.order);

  factory Todo.fromJson(String id, Map<String, dynamic> data) =>
      Todo(id, data['listId'], data['text'], data['complete'], data['order']);

  Map<String, dynamic> toJson() {
    return {
      'listId': listId,
      'text': text,
      'complete': complete,
      'order': order,
    };
  }
}
