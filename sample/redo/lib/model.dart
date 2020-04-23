class Todo {
  int id;
  num listId;
  String text;
  bool complete;
  num order;

  Todo(this.id, this.listId, this.text, this.complete, this.order);

  factory Todo.fromJson(Map<String, dynamic> data) => Todo(
        data['id'],
        data['listId'],
        data['text'],
        data['complete'],
        data['order'],
      );

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listId': listId,
      'text': text,
      'complete': complete,
      'order': order,
    };
  }
}
