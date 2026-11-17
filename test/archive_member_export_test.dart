import 'package:droidre_ai_studio/services/archive_member_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters supported member paths and safely names output', () {
    expect(ArchiveMemberExport.eligible('splits/base.apk'), true);
    expect(ArchiveMemberExport.eligible('lib/arm64-v8a/libil2cpp.so'), true);
    expect(ArchiveMemberExport.eligible('assets/index.android.bundle'), true);
    expect(ArchiveMemberExport.eligible('../base.apk'), false);
    expect(ArchiveMemberExport.eligible('x\\base.apk'), false);
    expect(ArchiveMemberExport.eligible('classes.dex'), false);
    expect(ArchiveMemberExport.outputName('splits/base.apk'), 'member-base.apk');
  });
}
