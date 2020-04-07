import 'dart:async';

import 'package:flutter/material.dart';
import 'package:redo/login.dart';
import 'package:replicache/replicache.dart';
import 'package:uuid/uuid.dart';

import 'model.dart';
import 'settings.dart';

void main() => runApp(MyApp());

const prefix = '/todo/';

String stripPrefix(String id) => id.substring(prefix.length);

String addPrefix(String id) => '$prefix$id';

class MyApp extends StatelessWidget {
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
  List<int> _listIds = [];
  List<Todo> _allTodos = [];
  bool _syncing = false;
  int _selectedListId;

  LoginResult _loginResult;
  LoginPrefs _loginPrefs;

  _MyHomePageState() {
    _loginPrefs = LoginPrefs(() => context);
    _init();
  }

  Future<String> _getAuthToken() async {
    final user = await _loginPrefs.loggedInUser();
    return user?.userId ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Todo List'),
        actions: _syncing ? [Icon(Icons.sync)] : [],
      ),
      drawer: TodoDrawer(
        listIds: _listIds,
        selectedListId: _selectedListId,
        onSelectListId: _selectListId,
        onSync: _replicache?.sync,
        onDrop: _dropDatabase,
        email: _loginResult?.email,
        logout: _logout,
      ),
      body: TodoList(
        _activeTodos(),
        _handleDone,
        _handleRemove,
        _handleReorder,
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _pushAddTodoScreen,
          tooltip: 'Add task',
          child: Icon(Icons.add)),
    );
  }

  Future<void> _init() async {
    var loginResult = await _loginPrefs.login();

    _replicache = Replicache(db, name: loginResult.userId);
    _replicache.onChange = _load;
    _replicache.onSync = _handleSync;
    _replicache.getAuthToken = _getAuthToken;
    _replicache.clientViewAuth = loginResult.userId;

    setState(() {
      _loginResult = loginResult;
    });

    await _load();
  }

  Future<void> _load() async {
    List<int> listIds = List.from((await _replicache.scan(prefix: '/list/'))
        .map((item) => int.parse(item.id.substring('/list/'.length))));

    if (_selectedListId == null && listIds.length > 0) {
      setState(() {
        _selectedListId = listIds[0];
      });
    }

    setState(() {
      _listIds = listIds;
    });

    List<Todo> allTodos = List.from((await _replicache.scan(prefix: prefix))
        .map((item) => Todo.fromJson(stripPrefix(item.id), item.value)));
    setState(() {
      _allTodos = allTodos;
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

  Future<void> _handleDone(String id, bool complete) async {
    var todo = await _read(id);
    if (todo == null) {
      return;
    }
    todo.complete = complete;
    _write(id, todo);
  }

  List<Todo> _activeTodos() {
    List<Todo> todos =
        List.from(_allTodos.where((todo) => todo.listId == _selectedListId));
    todos.sort((t1, t2) => (t1.order - t2.order).sign.toInt());
    return todos;
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    List<Todo> todos = _activeTodos();
    String id = todos[oldIndex].id;
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

  void _selectListId(int listId) {
    setState(() {
      _selectedListId = listId;
    });
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
      List<Todo> todos = _activeTodos();
      int index = todos.length == 0 ? 0 : todos.length;
      String id = uuid.v4();
      double order = _getNewOrder(index);
      await _write(id, Todo(id, _selectedListId, task, false, order));
    }
  }

  // calculates the order field by halving the distance between the left and right neighbor orders.
  // min default value = -minPositive
  // max default value = double.maxFinite
  double _getNewOrder(int index) {
    List<Todo> todos = _activeTodos();
    double minOrderValue = 0;
    double maxOrderValue = double.maxFinite;
    double leftNeighborOrder =
        index == 0 ? minOrderValue : todos[index - 1].order.toDouble();
    double rightNeighborOrder =
        index == todos.length ? maxOrderValue : todos[index].order.toDouble();
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
      return Scaffold(
        appBar: AppBar(title: new Text('Add a new task')),
        body: TextField(
          autofocus: true,
          onSubmitted: (val) {
            _addTodoItem(val);
            Navigator.pop(context); // Close the add todo screen
          },
          decoration: new InputDecoration(
              hintText: 'Enter something to do...',
              contentPadding: const EdgeInsets.all(16.0)),
        ),
      );
    }));
  }

  void _logout() async {
    await _loginPrefs.logout();

    await _replicache.close();
    _replicache = null;

    setState(() {
      _selectedListId = null;
      _loginResult = null;
      _allTodos = [];
      _listIds = [];
    });

    _init();
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
              title: new Text(todo.text),
              value: todo.complete,
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
  final Future<void> Function() onSync;
  final Future<void> Function() onDrop;
  final void Function(int id) onSelectListId;
  final List<int> listIds;
  final int selectedListId;
  final String email;

  final void Function() logout;

  TodoDrawer({
    this.listIds = const [],
    this.onSync,
    this.onDrop,
    @required this.selectedListId,
    @required this.onSelectListId,
    @required this.logout,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      UserAccountsDrawerHeader(
        currentAccountPicture: CircleAvatar(
          child: Text(
            email?.substring(0, 1)?.toUpperCase() ?? '',
            style: TextStyle(fontSize: 50),
          ),
        ),
        accountName: Text(''),
        accountEmail: Text(email ?? ''),
        decoration: BoxDecoration(
          color: Colors.blue,
        ),
      ),
      ListTile(
        title: Text(
          "LISTS",
          style: TextStyle(
            letterSpacing: 3,
            fontWeight: FontWeight.normal,
            color: Colors.grey,
          ),
        ),
      ),
    ];
    children.addAll(listIds.map((id) => ListTile(
        title: Text('List #$id'),
        selected: selectedListId == id,
        onTap: () {
          onSelectListId(id);
          Navigator.pop(context);
        })));
    children.add(Divider());
    children.add(
      ListTile(
        title: Text('Sync'),
        onTap: onSync,
      ),
    );
    if (onDrop != null) {
      children.add(
        ListTile(
          title: Text('Delete local state'),
          onTap: onDrop,
        ),
      );
    }
    children.add(
      ListTile(
        title: Text('Logout'),
        onTap: () async {
          Navigator.pop(context);
          logout();
        },
      ),
    );
    return Drawer(child: ListView(children: children));
  }
}
