import 'package:droidre_ai_studio/services/adb_device_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory report uses an explicit validated package', () {
    expect(AdbDeviceInspector.memoryArgs('ABC', 'com.demo'),
      ['-s', 'ABC', 'shell', 'dumpsys', 'meminfo', 'com.demo']);
    expect(() => AdbDeviceInspector.memoryArgs('ABC', 'bad;command'), throwsFormatException);
  });
  test('parses only recognized states and deduplicates devices', () {
    final devices = AdbDeviceInspector.parseDevices(
      'List of devices attached\nABC123\tdevice model:Demo\n'
      'ABC123\tdevice\n192.168.1.5:5555\toffline\nXYZ\tunauthorized\n');
    expect(devices.map((d) => d.serial), ['ABC123', '192.168.1.5:5555', 'XYZ']);
    expect(devices.map((d) => d.authorized), [true, false, false]);
  });

  test('filters package names and sorts inventory', () {
    expect(AdbDeviceInspector.parsePackages(
      'package:z.demo\npackage:a.demo\npackage:a.demo\npackage:bad;cmd\n'),
      ['a.demo', 'z.demo']);
  });

  test('rejects shell metacharacters and flag injection', () {
    expect(() => AdbDeviceInspector.packagePathArgs('ABC', 'app;id'),
      throwsFormatException);
    expect(() => AdbDeviceInspector.packagePathArgs('-s', 'com.demo'),
      throwsFormatException);
    expect(() => AdbDeviceInspector.logArgs('ABC', 0), throwsFormatException);
  });

  test('scopes commands to explicit serial, package and PID', () {
    expect(AdbDeviceInspector.packagePathArgs('ABC', 'com.demo'),
      ['-s', 'ABC', 'shell', 'pm', 'path', 'com.demo']);
    expect(AdbDeviceInspector.logArgs('ABC', 123),
      ['-s', 'ABC', 'logcat', '--pid=123', '-d', '-t', '300', '-v', 'threadtime']);
  });
}
