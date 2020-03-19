/// DatabaseInfo contains information about available local databases.
class DatabaseInfo {
  DatabaseInfo.fromJson(Map<String, dynamic> data) : name = data['name'];
  String name;
}
