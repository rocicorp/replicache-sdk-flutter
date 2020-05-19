class ScanItem {
  ScanItem.fromJson(Map<String, dynamic> data)
      : key = data['key'],
        value = data['value'];
  final String key;

  final dynamic value;

  @Deprecated('Use key instead')
  get id => key;
}
