import 'dart:async';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:redo/login.dart';
import 'package:replicache/replicache.dart';
import 'package:replicache/src/log.dart';

import 'model.dart';
import 'settings.dart';

void main() => runApp(MyApp());

const prefix = '/todo/';
final _firebaseMessaging = FirebaseMessaging();

String addPrefix(int id) => '$prefix$id';

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
  Iterable<Todo> _allTodos = [];
  bool _online = true;
  bool _syncing = false;
  int _selectedListId;
  bool _deleteMode = false;

  LoginResult _loginResult;
  LoginPrefs _loginPrefs;

  final Random _random = Random.secure();

  _MyHomePageState() {
    // Note: this is a no-op on Android.
    _firebaseMessaging.requestNotificationPermissions(
      const IosNotificationSettings(sound: true, badge: true, alert: true, provisional: false),
    );
    _firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> message) async {
        _replicache.sync();
      },
    );

    _loginPrefs = LoginPrefs(() => context);
    _init();
  }

  Future<String> _getDataLayerAuth() async {
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
    var icons = List<Widget>();
    if (_syncing) {
      icons = [Icon(Icons.sync)];
    } else if (!_online) {
      icons = [IconButton(
        icon: Icon(Icons.sync_disabled),
        onPressed: () => this._replicache.sync(),
        padding: EdgeInsets.all(0.0))];
    }
    icons.add(IconButton(
        icon: Icon(Icons.delete),
        onPressed: () {
          setState(() {
            _deleteMode = !_deleteMode;
          });
        }));
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('Todo List'),
        actions: icons,
        centerTitle: false,
      ),
      drawer: TodoDrawer(
        selectedListId: _selectedListId,
        onSelectListId: _selectListId,
        onSync: _replicache?.sync,
        onDrop: _dropDatabase,
        onFakeId: _setFakeUserId,
        email: _loginResult?.email,
        logout: _logout,
      ),
      body: TodoList(
        todosInList(_allTodos, _selectedListId),
        _deleteMode,
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
    debug("FCM token: " + await _firebaseMessaging.getToken());
  }

  Future<void> _initWithLoginResult(LoginResult loginResult) async {
    _replicache = Replicache(
      diffServerUrl: diffServerUrl,
      name: loginResult.userId,
      dataLayerAuth: loginResult.userId,
      diffServerAuth: diffServerAuth,
      batchUrl: batchUrl,
    );
    _replicache.onSync = _handleSync;
    _replicache.getDataLayerAuth = _getDataLayerAuth;

    if (_loginResult != null) {
      _firebaseMessaging.unsubscribeFromTopic("u-" + _loginResult.userId);
    }
    _firebaseMessaging.subscribeToTopic("u-" + loginResult.userId);
    debug("Subscribed to topic: u-" + loginResult.userId);

    _registerMutations();

    setState(() {
      _loginResult = loginResult;
    });

    _listIdStream().listen((listIds) {
      setState(() {
        if ((_selectedListId == null || !listIds.contains(_selectedListId)) &&
            listIds.isNotEmpty) {
          _selectedListId = listIds.first;
        }
      });
    });

    _todoStream().listen((allTodos) {
      setState(() {
        debug("num todos at setState: " + allTodos.length.toString());
        _allTodos = allTodos;
      });
    });
  }

  Stream<Iterable<int>> _listIdStream() => _replicache.subscribe(
        (tx) async => (await tx.scan(prefix: '/list/', limit: 500)).map(
          (item) => item.value['id'],
        ),
      );

  Stream<Iterable<Todo>> _todoStream() => _replicache.subscribe(allTodosInTx);

  void _handleSync(bool syncing) {
    setState(() {
      _online = _replicache.online;
      _syncing = syncing;
    });
  }

  static Future<Todo> _read(ReadTransaction tx, int id) async {
    final data = await tx.get(addPrefix(id));
    return data == null ? null : Todo.fromJson(data);
  }

  static Future<void> _write(WriteTransaction tx, Todo todo) {
    final key = addPrefix(todo.id);
    return tx.put(key, todo);
  }

  static Future<bool> _del(WriteTransaction tx, int id) =>
      tx.del(addPrefix(id));

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

  Mutator _createTodo;
  Mutator _deleteTodo;
  Mutator _updateTodo;

  _registerMutations() {
    _createTodo = _replicache.register('createTodo', (tx, args) async {
      await _write(tx, Todo.fromJson(args));
    });

    _deleteTodo = _replicache.register('deleteTodo', (tx, args) async {
      int id = args['id'];
      await _del(tx, id);
    });

    _updateTodo = _replicache.register('updateTodo', (tx, args) async {
      int id = args['id'];
      final todo = await _read(tx, id);
      if (todo == null) {
        info('Warning: Possible conflict - Specified Todo $id is not present.'
            ' Skipping reorder.');
        return;
      }
      todo.text = args['text'] ?? todo.text;
      todo.complete = args['complete'] ?? todo.complete;
      todo.order = args['order'] ?? todo.order;
      await _write(tx, todo);
    });
  }

  Future<void> _addTodoItem(String text) async {
    // Only add the task if the user actually entered something
    if (text.isEmpty) {
      return;
    }

    int id = _random.nextInt(1 << 31);

    Iterable<Todo> todos = todosInList(_allTodos, _selectedListId);
    final order = newOrderBetween(todos.isEmpty ? null : todos.last, null);

    await _createTodo({
      'id': id,
      'listId': _selectedListId,
      'text': text,
      'complete': false,
      'order': order,
    });
    _replicache.sync();
  }

  void _handleDone(int id, bool complete) {
    _updateTodo({'id': id, 'complete': complete});
    _replicache.sync();
  }

  void _handleRemove(int id) {
    setState(() {
      _deleteMode = false;
    });
    _deleteTodo({'id': id});
    _replicache.sync();
  }

  void _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) {
      return;
    }

    final todos = todosInList(_allTodos, _selectedListId).toList();
    if (newIndex == todos.length && oldIndex == todos.length - 1) {
      return;
    }

    int id = todos[oldIndex].id;
    Todo left;
    Todo right;
    if (newIndex == 0) {
      right = todos.first;
    } else if (newIndex == todos.length) {
      left = todos.last;
    } else {
      left = newIndex > 0 ? todos[newIndex - 1] : null;
      right = newIndex < todos.length ? todos[newIndex] : null;
    }

    double order = newOrderBetween(left, right);
    _updateTodo({'id': id, 'order': order});
    _replicache.sync();
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
    });
  }

  void _setFakeUserId() async {
    await _loginPrefs.logout();
    await _clearState();
    _initWithLoginResult(LoginResult('fake@roci.dev', '11111111'));
    Navigator.pop(context);
  }
}

class TodoList extends StatelessWidget {
  final bool _deleteMode;
  final List<Todo> _todos;
  final void Function(int, bool) _handleDone;
  final void Function(int) _handleRemove;
  final void Function(int, int) _handleReorder;

  TodoList(this._todos, this._deleteMode, this._handleDone, this._handleRemove,
      this._handleReorder);

  // Build the whole list of todo items
  @override
  Widget build(BuildContext build) {
    return _buildReorderableListView(build);

    // builds a listview of todo items. not called right now but just keeping it as sample code.
    //return _buildListView(build);
  }

  // builds a reorderable list, reorder functionality is achieved by dragging and dropping list items.
  Widget _buildReorderableListView(BuildContext context) {
    debug("num todos: " + this._todos.length.toString());
    return ReorderableListView(
      children: List.generate(_todos.length, (index) {
        var todo = _todos[index];
        var id = todo.id;
        if (_deleteMode) {
          return ListTile(
              key: Key('$id'),
              title: Text(todo.text),
              trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () {
                    _handleRemove(id);
                  }));
        }
        return CheckboxListTile(
            key: Key('$id'),
            title: Text(todo.text),
            value: todo.complete,
            onChanged: (bool newValue) {
              _handleDone(id, newValue);
            });
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
  final int selectedListId;
  final String email;

  final void Function() logout;
  final void Function() onFakeId;

  TodoDrawer({
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
        title: Text('Sync'),
        onTap: onSync,
      ),
    ];
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

Future<Iterable<Todo>> allTodosInTx(ReadTransaction tx) async =>
    (await tx.scan(prefix: prefix, limit: 500))
        .map((scanItem) => Todo.fromJson(scanItem.value));

List<Todo> todosInList(Iterable<Todo> allTodos, int listId) {
  final todos = allTodos.where((todo) => todo.listId == listId).toList();
  todos.sort((t1, t2) => (t1.order - t2.order).sign.toInt());
  return todos;
}

Future<Iterable<Todo>> todosInListFromTx(
        ReadTransaction tx, int listId) async =>
    todosInList(await allTodosInTx(tx), listId);

double newOrder(double before, double after) {
  const double minOrderValue = 0;
  const double maxOrderValue = double.maxFinite;
  if (before == null) {
    before = minOrderValue;
  }
  if (after == null) {
    after = maxOrderValue;
  }
  return before + (after - before) / 2;
}

/// calculates the order field by halving the distance between the left and right
/// neighbor orders.
/// min default value = -minPositive
/// max default value = double.maxFinite
double newOrderBetween(Todo left, Todo right) {
  final leftOrder = left?.order?.toDouble();
  final rightOrder = right?.order?.toDouble();
  return newOrder(leftOrder, rightOrder);
}
