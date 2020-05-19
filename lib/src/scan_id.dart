class ScanId {
  ScanId(this.value, this.exclusive);
  final String value;
  final bool exclusive;
  Map<String, dynamic> toJson() {
    return {
      'value': value ?? '',
      'exclusive': exclusive ?? false,
    };
  }
}
