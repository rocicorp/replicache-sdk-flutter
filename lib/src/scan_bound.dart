import './scan_id.dart';

class ScanBound {
  ScanBound(this.id, this.index);
  final ScanId id;
  final int index;
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> r = {};
    if (this.id != null) {
      r['id'] = this.id;
    }
    if (this.index != null) {
      r['index'] = this.index;
    }
    return r;
  }
}
