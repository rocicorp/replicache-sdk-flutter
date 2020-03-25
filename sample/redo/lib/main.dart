import 'dart:async';

import 'package:flutter/material.dart';
import 'package:replicache/replicache.dart';
import 'package:uuid/uuid.dart';

import 'model.dart';
import 'settings.dart';

void main() => runApp(MyApp());

const prefix = 'todo/';

String stripPrefix(String id) => id.substring(prefix.length);

String addPrefix(String id) => "$prefix$id";

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  Replicache _replicache;
  List<Todo> _todos = [];
  bool _syncing = false;

  _MyHomePageState() {
    _replicache = Replicache(db, clientViewUserId: "42");
    _replicache.onChange = this._load;
    _replicache.onSync = this._handleSync;
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      key: _scaffoldKey,
      appBar: new AppBar(
        title: new Text('Todo List'),
        actions: _syncing ? [Icon(Icons.sync)] : [],
      ),
      drawer: TodoDrawer(_replicache.sync, _dropDatabase),
      body: TodoList(_todos, _handleDone, _handleRemove, _handleReorder),
      floatingActionButton: new FloatingActionButton(
          onPressed: _pushAddTodoScreen,
          tooltip: 'Add task',
          child: new Icon(Icons.add)),
    );
  }

  Future<void> _init() async {
    // TODO(arv): Do we still need init
    await _load();
  }

  Future<void> _load() async {
    List<Todo> todos = List.from((await _replicache.scan(prefix: prefix))
        .map((item) => Todo.fromJson(stripPrefix(item.id), item.value)));
    todos.sort(
        (t1, t2) => t1.order < t2.order ? -1 : t1.order == t2.order ? 0 : 1);
    setState(() {
      _todos = todos;
    });
  }

  void _handleSync(bool syncing) {
    setState(() {
      _syncing = syncing;
    });
  }

  Future<Todo> _read(String id) async {
    final data = await _replicache.get(addPrefix(id));
    return data == null ? null : Todo.fromJson(id, data);
  }

  Future<void> _write(String id, Todo todo) {
    return _replicache.put(addPrefix(id), todo.toJson());
  }

  Future<void> _del(String id) {
    return _replicache.del(addPrefix(id));
  }

  Future<void> _handleDone(String id, bool isDone) async {
    var todo = await _read(id);
    if (todo == null) {
      return;
    }
    todo.done = isDone;
    _write(id, todo);
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    String id = this._todos[oldIndex].id;
    double order = _getNewOrder(newIndex);
    var todo = await _read(id);
    if (todo == null) {
      return;
    }
    todo.order = order;
    _write(id, todo);
  }

  Future<void> _handleRemove(String id) async {
    await _del(id);
  }

  Future<void> _dropDatabase() async {
    Navigator.pop(context);
    var items = await _replicache.scan(prefix: prefix);
    for (final ScanItem item in items) {
      await _replicache.del(item.id);
    }
    await _init();
  }

  Future<void> _addTodoItem(String task) async {
    var uuid = new Uuid();
    // Only add the task if the user actually entered something
    if (task.length > 0) {
      int index = _todos.length == 0 ? 0 : _todos.length;
      String id = uuid.v4();
      double order = _getNewOrder(index);
      await _write(id, Todo(id, task, false, order));
    }
  }

  // calculates the order field by halving the distance between the left and right neighbor orders.
  // min default value = -minPositive
  // max default value = double.maxFinite
  double _getNewOrder(int index) {
    double minOrderValue = 0;
    double maxOrderValue = double.maxFinite;
    double leftNeighborOrder =
        index == 0 ? minOrderValue : _todos[index - 1].order.toDouble();
    double rightNeighborOrder =
        index == _todos.length ? maxOrderValue : _todos[index].order.toDouble();
    double order =
        leftNeighborOrder + ((rightNeighborOrder - leftNeighborOrder) / 2);
    return order;
  }

  void _pushAddTodoScreen() {
    // Push this page onto the stack
    Navigator.of(context).push(
        // MaterialPageRoute will automatically animate the screen entry, as well as adding
        // a back button to close it
        new MaterialPageRoute(builder: (context) {
      return new Scaffold(
          appBar: new AppBar(title: new Text('Add a new task')),
          body: new TextField(
            autofocus: true,
            onSubmitted: (val) {
              _addTodoItem(val);
              Navigator.pop(context); // Close the add todo screen
            },
            decoration: new InputDecoration(
                hintText: 'Enter something to do...',
                contentPadding: const EdgeInsets.all(16.0)),
          ));
    }));
  }
}

class TodoList extends StatelessWidget {
  final List<Todo> _todos;
  final Future<void> Function(String, bool) _handleDone;
  final Future<void> Function(String) _handleRemove;
  final Future<void> Function(int, int) _handleReorder;

  TodoList(
      this._todos, this._handleDone, this._handleRemove, this._handleReorder);

  // Build the whole list of todo items
  @override
  Widget build(BuildContext build) {
    return _buildReorderableListView(build);

    // builds a listview of todo items. not called right now but just keeping it as sample code.
    //return _buildListView(build);
  }

  // builds a reorderable list, reorder functionality is achieved by dragging and dropping list items.
  Widget _buildReorderableListView(BuildContext context) {
    return ReorderableListView(
      children: List.generate(_todos.length, (index) {
        var todo = _todos[index];
        var id = todo.id;
        return Dismissible(
          key: Key(id),
          onDismissed: (direction) {
            _handleRemove(id);
          },
          // Show a red background as the item is swiped away.
          background: Container(color: Colors.red),
          child: new CheckboxListTile(
              title: new Text(todo.title),
              value: todo.done,
              onChanged: (bool newValue) {
                _handleDone(id, newValue);
              }),
        );
      }),
      onReorder: (int oldIndex, int newIndex) {
        _handleReorder(oldIndex, newIndex);
      },
    );
  }
}

class TodoDrawer extends StatelessWidget {
  final Future<void> Function() _sync;
  final Future<void> Function() _dropDatabase;

  TodoDrawer(this._sync, this._dropDatabase);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: <Widget>[
          DrawerHeader(
            child: Text(""),
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
          ),
          ListTile(
            title: Text('Sync'),
            onTap: _sync,
          ),
          ListTile(
            title: Text('Delete local state'),
            onTap: _dropDatabase,
          ),
        ],
      ),
    );
  }
}
