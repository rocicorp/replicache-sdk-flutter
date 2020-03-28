import 'package:flutter/material.dart';
import 'package:replicache/replicache.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  Replicache _replicache;

  _MyHomePageState() {
    this.init();
  }

  void init() async {
    _replicache = Replicache('https://serve.replicate.to/sandbox/demo-counter',
        clientViewAuth: "");
    _replicache.onChange = this._handleChange;
    _replicache.onSync = this._handleSync;
    this._handleChange();
  }

  Future<int> _getCount() async {
    final count = await _replicache.get('count');
    return count ?? 0;
  }

  Future<void> _incrementCounter() async {
    final count = await _getCount();
    await _replicache.put('count', count + 1);
  }

  void _handleChange() async {
    final count = await _getCount();
    setState(() {
      _counter = count;
    });
  }

  void _handleSync(bool syncing) {
    if (syncing) {
      print('Syncing...');
    } else {
      print('Done');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}
