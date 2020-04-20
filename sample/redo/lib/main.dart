import 'dart:async';

import 'package:flutter/material.dart';
import 'package:redo/login.dart';
import 'package:replicache/replicache.dart';
import 'package:uuid/uuid.dart';

import 'model.dart';
import 'settings.dart';

void main() => runApp(MyApp());

const prefix = '/todo/';

String stripPrefix(String key) => key.substring(prefix.length);

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
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Authentication failed'),
          content: Text('Please login again'),
          actions: <Widget>[
            FlatButton(
              child: Text('Ok'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    var loginResult = await _loginPrefs.login();
    return loginResult.userId;
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
        onFakeId: _setFakeUserId,
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
    await _initWithLoginResult(loginResult);
  }

  Future<void> _initWithLoginResult(LoginResult loginResult) async {
    _replicache = Replicache(
      db,
      name: loginResult.userId,
      clientViewAuth: loginResult.userId,
    );
    _replicache.onChange = _load;
    _replicache.onSync = _handleSync;
    _replicache.getClientViewAuth = _getAuthToken;

    setState(() {
      _loginResult = loginResult;
    });

    await _load();
  }

  Future<void> _load() async {
    final res = await _replicache.query((tx) async {
      return await Future.wait(
          [tx.scan(prefix: '/list/'), tx.scan(prefix: prefix)]);
    });

    final listIdScanItems = res[0];
    final todosScanItems = res[1];

    List<int> listIds = List.from(listIdScanItems
        .map((item) => int.parse(item.key.substring('/list/'.length))));
    List<Todo> allTodos = List.from(todosScanItems
        .map((item) => Todo.fromJson(stripPrefix(item.key), item.value)));

    setState(() {
      if ((_selectedListId == null || !listIds.contains(_selectedListId)) &&
          listIds.length > 0) {
        _selectedListId = listIds[0];
      }
      _listIds = listIds;
      _allTodos = allTodos;
    });
  }

  void _handleSync(bool syncing) {
    setState(() {
      _syncing = syncing;
    });
  }

  Future<Todo> _read(ReadTransaction tx, String id) async {
    final data = await tx.get(addPrefix(id));
    return data == null ? null : Todo.fromJson(id, data);
  }

  Future<void> _write(dynamic tx, String id, Todo todo) {
    return Future.error('Not implemented');
    // return _replicache.put(addPrefix(key), todo.toJson());
  }

  Future<void> _del(dynamic tx, String id) {
    throw UnimplementedError();
    // return _replicache.del(addPrefix(key));
  }

  Future<void> _handleDone(String id, bool complete) async {
    // TODO(arv): This should be mutate
    _replicache.query((tx) async {
      var todo = await _read(tx, id);
      if (todo == null) {
        return;
      }
      todo.complete = complete;
      _write(tx, id, todo);
    });
  }

  List<Todo> _activeTodos() {
    if (_selectedListId == null) {}
    List<Todo> todos =
        List.from(_allTodos.where((todo) => todo.listId == _selectedListId));
    todos.sort((t1, t2) => (t1.order - t2.order).sign.toInt());
    return todos;
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    List<Todo> todos = _activeTodos();
    String id = todos[oldIndex].id;
    double order = _getNewOrder(newIndex);
    // TODO(arv): Should be mutate
    _replicache.query((tx) async {
      var todo = await _read(tx, id);
      if (todo == null) {
        return;
      }
      todo.order = order;
      _write(tx, id, todo);
    });
  }

  Future<void> _handleRemove(String id) async {
    // TODO(arv): Should be mutate
    _replicache.query((tx) async {
      await _del(tx, id);
    });
  }

  void _selectListId(int listId) {
    setState(() {
      _selectedListId = listId;
    });
  }

  Future<void> _dropDatabase() async {
    throw UnimplementedError();
    // Navigator.pop(context);
    // var items = await _replicache.scan(prefix: prefix);
    // for (final ScanItem item in items) {
    //   await _replicache.del(item.key);
    // }
    // await _init();
  }

  Future<void> _addTodoItem(String task) async {
    var uuid = new Uuid();
    // Only add the task if the user actually entered something
    if (task.length > 0) {
      List<Todo> todos = _activeTodos();
      int index = todos.length == 0 ? 0 : todos.length;
      String id = uuid.v4();
      double order = _getNewOrder(index);
      // TODO(arv): Should be mutate and maybe include _activeTodos.
      _replicache.query((tx) async {
        await _write(tx, id, Todo(id, _selectedListId, task, false, order));
      });
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
    await _clearState();
    _init();
  }

  Future<void> _clearState() async {
    await _replicache.close();
    _replicache = null;

    setState(() {
      _selectedListId = null;
      _loginResult = null;
      _allTodos = [];
      _listIds = [];
    });
  }

  void _setFakeUserId() async {
    await _loginPrefs.logout();
    await _clearState();
    _initWithLoginResult(LoginResult("fake@roci.dev", "11111111"));
    Navigator.pop(context);
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
  final void Function() onFakeId;

  TodoDrawer({
    this.listIds = const [],
    this.onSync,
    this.onDrop,
    this.onFakeId,
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
    if (onFakeId != null) {
      children.add(
        ListTile(
          title: Text('Change to invalid user ID'),
          onTap: onFakeId,
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
