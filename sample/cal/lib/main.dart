import 'package:flutter/material.dart';
import 'package:replicache/replicache.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calendar',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'My Calendar'),
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
  List<Map<String, dynamic>> _events = [];
  Replicache _replicache = new Replicache('http://localhost:7001');

  _MyHomePageState() {
    _replicache.onChange = _handleChange;
    _replicache.onChange();
  }
  
  void _handleChange() async {
    var events = List<Map<String, dynamic>>.from(
      (await _replicache.scan(prefix: '/event/')).map((item) => item.value));
    setState(() {
      _events = events;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.from(
            _events.map(
              (Map m) => Text(m['time'] + ': ' + m['title']))),
        ),
      ),
    );
  }
}
