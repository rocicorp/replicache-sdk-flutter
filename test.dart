class C {
  bool b;
  C();
  m() => b;
}

main() {
  dynamic c = C();
  print(c.m());
}
