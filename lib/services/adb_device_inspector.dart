import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class AdbDevice {
  const AdbDevice(this.serial, this.state);
  final String serial, state;
  bool get authorized => state == 'device';
}

class AdbDeviceInspector {
  const AdbDeviceInspector(this.executable);
  final String executable;
  static const maxOutput = 512 * 1024;

  static bool validSerial(String serial) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$').hasMatch(serial);
  static bool validPackage(String package) =>
      package.length <= 255 &&
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)+$').hasMatch(package);

  static List<AdbDevice> parseDevices(String text) {
    final devices = <AdbDevice>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2 || !validSerial(fields.first) ||
          !const {'device', 'offline', 'unauthorized', 'recovery', 'sideload', 'bootloader'}.contains(fields[1]) ||
          !seen.add(fields.first)) {
        continue;
      }
      devices.add(AdbDevice(fields.first, fields[1]));
      if (devices.length >= 64) {
        break;
      }
    }
    return devices;
  }

  static List<String> parsePackages(String text) {
    final packages = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('package:')) {
        continue;
      }
      final name = line.substring(8).trim();
      if (validPackage(name)) {
        packages.add(name);
      }
    }
    return packages.toList()..sort();
  }

  static List<String> packagePathArgs(String serial, String package) {
    if (!validSerial(serial) || !validPackage(package)) {
      throw const FormatException('Invalid device serial or package name');
    }
    return ['-s', serial, 'shell', 'pm', 'path', package];
  }

  static List<String> logArgs(String serial, int pid) {
    if (!validSerial(serial) || pid <= 0 || pid > 0x7fffffff) {
      throw const FormatException('Invalid device serial or PID');
    }
    return ['-s', serial, 'logcat', '--pid=$pid', '-d', '-t', '300', '-v', 'threadtime'];
  }

  Future<String> _run(List<String> args) async {
    if (!Platform.isWindows || !p.isAbsolute(executable) ||
        p.basename(executable).toLowerCase() != 'adb.exe' ||
        !await File(executable).exists()) {
      throw const FormatException('Select trusted Android SDK platform-tools adb.exe');
    }
    final process = await Process.start(executable, args, runInShell: false);
    final out = StringBuffer();
    final err = StringBuffer();
    var clipped = false;
    void append(StringBuffer buffer, String chunk) {
      final left = maxOutput - buffer.length;
      if (chunk.length > left) {
        clipped = true;
      }
      if (left > 0) {
        buffer.write(chunk.substring(0, chunk.length.clamp(0, left).toInt()));
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) => append(out, chunk));
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) => append(err, chunk));
    try {
      final result = await Future.wait<Object?>([
        process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
      ]).timeout(const Duration(seconds: 25));
      if (result.first != 0) {
        throw FormatException('ADB failed (exit ${result.first}): $err');
      }
      if (clipped) {
        throw const FormatException('ADB output exceeded inspection limit');
      }
      return out.toString();
    } finally {
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
  }

  Future<List<AdbDevice>> devices() async => parseDevices(await _run(['devices', '-l']));

  Future<void> _requireDevice(String serial) async {
    if (!validSerial(serial) ||
        !(await devices()).any((d) => d.serial == serial && d.authorized)) {
      throw const FormatException('Device not connected and authorized');
    }
  }

  Future<Map<String, String>> properties(String serial) async {
    await _requireDevice(serial);
    final result = <String, String>{};
    for (final key in const ['ro.product.model', 'ro.product.manufacturer',
      'ro.build.version.release', 'ro.build.version.sdk', 'ro.product.cpu.abilist']) {
      result[key] = (await _run(['-s', serial, 'shell', 'getprop', key])).trim();
    }
    return result;
  }

  Future<List<String>> packages(String serial) async {
    await _requireDevice(serial);
    return parsePackages(await _run(['-s', serial, 'shell', 'pm', 'list', 'packages', '-3']));
  }

  Future<String> packagePaths(String serial, String package) async {
    await _requireDevice(serial);
    return _run(packagePathArgs(serial, package));
  }

  static List<String> memoryArgs(String serial, String package) {
    if (!validSerial(serial) || !validPackage(package)) {
      throw const FormatException('Invalid device or package');
    }
    return ['-s', serial, 'shell', 'dumpsys', 'meminfo', package];
  }

  Future<String> memoryInfo(String serial, String package) async {
    await _requireDevice(serial);
    return _run(memoryArgs(serial, package));
  }

  static List<String> liveLogArgs(String serial, int pid) {
    if (!validSerial(serial) || pid <= 0 || pid > 0x7fffffff) {
      throw const FormatException('Invalid device serial or PID');
    }
    return ['-s', serial, 'logcat', '--pid=$pid', '-T', '1', '-v', 'threadtime'];
  }

  Future<String> liveLogs(String serial, String package,
      {required bool Function() cancelled, required void Function(String) onUpdate}) async {
    if (!validPackage(package)) {
      throw const FormatException('Invalid package');
    }
    await _requireDevice(serial);
    final pid = int.tryParse((await _run(['-s', serial, 'shell', 'pidof', package])).trim());
    if (pid == null || pid <= 0 || cancelled()) {
      throw const FormatException('No single running main process or cancelled');
    }
    final process = await Process.start(executable, liveLogArgs(serial, pid), runInShell: false);
    final buffer = StringBuffer();
    var capped = false, stopped = false;
    void append(String part) {
      final remaining = maxOutput - buffer.length;
      if (remaining > 0) {
        buffer.write(part.substring(0, part.length.clamp(0, remaining).toInt()));
      }
      if (part.length > remaining) {
        capped = true;
        process.kill();
      }
    }
    final stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
    final stderr = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((_) {});
    final clock = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (cancelled() || clock.elapsed >= const Duration(seconds: 20)) {
        stopped = true;
        process.kill();
      } else {
        onUpdate('Live PID $pid · ${clock.elapsed.inSeconds}s · provisional\n$buffer');
      }
    });
    try {
      final results = await Future.wait<Object?>([
        process.exitCode, stdout.asFuture<void>(), stderr.asFuture<void>(),
      ]).timeout(const Duration(seconds: 26));
      timer.cancel();
      if (results.first != 0 && !stopped && !capped) {
        throw const FormatException('Live Logcat process failed');
      }
      if ((await _run(['-s', serial, 'shell', 'pidof', package])).trim() != '$pid') {
        throw const FormatException('Process changed; capture discarded');
      }
      return 'PID $pid · ${capped ? 'output capped' : 'bounded live capture ended'} · '
          'PID reuse remains possible\n$buffer';
    } finally {
      timer.cancel();
      process.kill();
      await stdout.cancel();
      await stderr.cancel();
    }
  }

  Future<String> logs(String serial, String package) async {
    if (!validPackage(package)) {
      throw const FormatException('Invalid package');
    }
    await _requireDevice(serial);
    final pids = (await _run(['-s', serial, 'shell', 'pidof', package]))
        .trim().split(RegExp(r'\s+'));
    if (pids.length != 1) {
      throw const FormatException('Select an app with one running main process');
    }
    final pid = int.tryParse(pids.single);
    if (pid == null || pid <= 0) {
      throw const FormatException('App main process is not running');
    }
    final output = await _run(logArgs(serial, pid));
    final after = (await _run(['-s', serial, 'shell', 'pidof', package])).trim();
    if (after != '$pid') {
      throw const FormatException('App process changed during log capture; retry');
    }
    return 'PID $pid · bounded log snapshot; PID reuse is possible.\n\n$output';
  }
}
