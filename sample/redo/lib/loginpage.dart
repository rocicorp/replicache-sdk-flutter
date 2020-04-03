import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:redo/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  final LoginPrefs loginPrefs;

  LoginPage({@required this.loginPrefs});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  Exception _error;

  @override
  Widget build(BuildContext context) {
    final themeData = ThemeData.dark().copyWith(
      accentColor: Colors.white70,
      backgroundColor: Colors.blue,
      buttonTheme: ButtonThemeData(buttonColor: Colors.blue[700]),
      errorColor: Colors.amberAccent,
    );
    return Scaffold(
      backgroundColor: themeData.backgroundColor,
      body: Theme(
        data: themeData,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Email',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onSaved: _onEmailEntered,
                      validator: (String val) {
                        return val == '' ? 'Email must not be empty.' : null;
                      },
                      textInputAction: TextInputAction.send,
                      onFieldSubmitted: _onEmailEntered,
                      autocorrect: false,
                      style: TextStyle(
                        decorationColor: Colors.white,
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.symmetric(vertical: 8),
                      child: RaisedButton(
                          child: Text(
                            'Login',
                          ),
                          onPressed: () {
                            if (_formKey.currentState.validate()) {
                              _formKey.currentState.save();
                            }
                          }),
                    ),
                    Text(
                      _error == null ? '' : _error.toString(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onEmailEntered(String email) async {
    setState(() {
      _error = null;
    });

    try {
      final loginResult = await widget.loginPrefs._login(email);
      Navigator.of(context).pop(loginResult);
    } catch (ex) {
      setState(() {
        _error = ex;
      });
    }
  }
}

class LoginResult {
  final String email;
  final int userId;
  const LoginResult(this.email, this.userId);

  Map<String, dynamic> toJson() {
    return {'email': email, 'userId': userId};
  }

  LoginResult.fromJson(Map<String, dynamic> json)
      : email = json['email'],
        userId = json['userId'].toInt();
}

class LoginPrefs {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  final BuildContext Function() _contextGetter;

  LoginPrefs(this._contextGetter);

  Future<LoginResult> loggedInUser() async {
    final p = await _prefs;
    final resJson = p.getString('loggedInUser');
    if (resJson == null) {
      return null;
    }
    return LoginResult.fromJson(json.decode(resJson));
  }

  Future<LoginResult> login() async {
    var loginResult = await loggedInUser();

    if (loginResult == null) {
      loginResult = await Navigator.pushAndRemoveUntil(
          _contextGetter(),
          MaterialPageRoute<LoginResult>(
            builder: (context) => LoginPage(
              loginPrefs: this,
            ),
            settings: RouteSettings(name: '/login'),
          ),
          ModalRoute.withName('/'));
    }

    return loginResult;
  }

  Future<LoginResult> _login(String email) async {
    final p = await _prefs;
    final resJson = p.getString('knownUsers');

    Map<String, dynamic> knownUsers =
        resJson != null ? json.decode(resJson) : {};
    int userId = knownUsers[email];
    if (userId == null) {
      userId = await _remoteLogin(email);
    }

    knownUsers[email] = userId;

    final user = LoginResult(email, userId);

    if (!(await p.setString('loggedInUser', json.encode(user.toJson())))) {
      throw Exception('Failed to store loggedInUser.');
    }

    if (!(await p.setString('knownUsers', json.encode(knownUsers)))) {
      throw Exception('Failed to store knownUsers.');
    }

    return user;
  }

  Future<int> _remoteLogin(String email) async {
    final resp = await http.put(loginUrl, body: json.encode({'email': email}));
    if (resp.statusCode == 200) {
      final val = json.decode(resp.body);
      return val['id'];
    } else {
      throw Exception('Failed to login. Status code: ${resp.statusCode}.');
    }
  }

  Future<void> logout() async {
    final p = await _prefs;
    if (!(await p.setString('loggedInUser', null))) {
      throw Exception('Failed to logout.');
    }
  }
}
