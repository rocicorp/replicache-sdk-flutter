/// DatabaseInfo contains information about available local databases.
class DatabaseInfo {
  DatabaseInfo.fromJson(Map<String, dynamic> data) : name = data['name'];
  final String name;
  @override
  bool operator ==(dynamic other) =>
      other is DatabaseInfo && other.name == name;
  @override
  int get hashCode => name.hashCode;
}
