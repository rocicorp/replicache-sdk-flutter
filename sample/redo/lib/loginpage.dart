import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:redo/settings.dart';

class LoginPage extends StatefulWidget {
  LoginPage();

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  Exception _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Theme(
        data: ThemeData.dark(),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'This demo app uses your email as authorization.',
                      style: ThemeData.dark().textTheme.body1,
                    ),
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
                        color: Colors.white,
                      ),
                    ),
                    FlatButton(
                        child: Text(
                          'Login',
                        ),
                        onPressed: () {
                          if (_formKey.currentState.validate()) {
                            _formKey.currentState.save();
                          }
                        }),
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
      final userId = await _getUserId(email);
      Navigator.of(context).pop(LoginResult(email, userId));
    } catch (ex) {
      setState(() {
        _error = ex;
      });
    }
  }

  Future<int> _getUserId(String email) async {
    final resp = await http.put(loginUrl, body: json.encode({"email": email}));
    if (resp.statusCode == 200) {
      final val = json.decode(resp.body);
      return val["id"];
    } else {
      throw Exception('Failed to login. Status code: ${resp.statusCode}');
    }
  }
}

class LoginResult {
  final String email;
  final int userId;
  const LoginResult(this.email, this.userId);
}
