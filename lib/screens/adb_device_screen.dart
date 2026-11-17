import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/adb_device_inspector.dart';

class AdbDeviceScreen extends StatefulWidget {
  const AdbDeviceScreen({super.key});

  @override
  State<AdbDeviceScreen> createState() => _AdbDeviceScreenState();
}

class _AdbDeviceScreenState extends State<AdbDeviceScreen> {
  String? _path, _serial, _package;
  List<AdbDevice> _devices = [];
  List<String> _packages = [];
  bool _trusted = false, _busy = false, _monitor = false;
  String _output = '', _filter = '';
  AdbDeviceInspector get _adb => AdbDeviceInspector(_path!);

  Future<void> _task(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _output = '';
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _output = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pick() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['exe']);
    final path = picked?.files.single.path;
    if (mounted && path != null) {
      setState(() {
        _path = path;
        _trusted = false;
        _devices = [];
        _packages = [];
        _serial = null;
        _package = null;
        _output = '';
      });
    }
  }

  Future<void> _refresh() async {
    final devices = await _adb.devices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _serial = null;
        _package = null;
        _packages = [];
        _output = '${devices.length} devices found';
      });
    }
  }

  Future<void> _loadPackages() async {
    final packages = await _adb.packages(_serial!);
    if (mounted) {
      setState(() {
        _packages = packages;
        _package = null;
        _output = '${packages.length} third-party packages';
      });
    }
  }

  Future<void> _show(Future<String> Function() read) async {
    final value = await read();
    if (mounted) {
      setState(() => _output = value);
    }
  }

  @override
  void dispose() {
    _monitor = false;
    super.dispose();
  }

  Future<void> _monitorLogs() async {
    final serial = _serial!;
    final package = _package!;
    final adb = _adb;
    setState(() => _monitor = true);
    try {
      for (var i = 0; i < 10 && _monitor && mounted; i++) {
        final snapshot = await adb.logs(serial, package);
        if (!mounted || !_monitor) {
          break;
        }
        setState(() => _output = 'Snapshot ${i + 1}/10 · ${DateTime.now().toIso8601String()}\n$snapshot');
        if (i < 9) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } finally {
      if (mounted) {
        setState(() => _monitor = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _trusted && _path != null && !_busy;
    final deviceReady = ready && _serial != null;
    final packageReady = deviceReady && _package != null;
    final visible = _packages.where((name) =>
        name == _package || name.toLowerCase().contains(_filter.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ADB Device Inspector')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Windows · trusted Android SDK platform-tools required. '
            'Authorize USB debugging on your own test device. Read-only inspection; '
            'no app installation, root, arbitrary shell or automatic uploads.'),
        OutlinedButton(onPressed: _busy ? null : _pick, child: Text(_path ?? 'Select adb.exe')),
        CheckboxListTile(value: _trusted,
          title: const Text('I trust this ADB executable and am authorized to inspect the connected device'),
          onChanged: _busy ? null : (value) => setState(() {
            _trusted = value ?? false;
            _output = '';
          })),
        FilledButton.icon(onPressed: ready ? () => _task(_refresh) : null,
          icon: const Icon(Icons.usb), label: const Text('Refresh connected devices')),
        if (_devices.isNotEmpty)
          for (final device in _devices)
            ListTile(
              title: Text(device.serial), subtitle: Text(device.state),
              selected: _serial == device.serial,
              trailing: _serial == device.serial ? const Icon(Icons.check) : null,
              onTap: ready && device.authorized ? () => setState(() {
                _serial = device.serial;
                _package = null;
                _packages = [];
                _output = '';
              }) : null,
            ),
        OutlinedButton(onPressed: deviceReady ? () => _task(() => _show(() async {
          final props = await _adb.properties(_serial!);
          return props.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
        })) : null, child: const Text('Read device properties')),
        OutlinedButton(onPressed: deviceReady ? () => _task(_loadPackages) : null,
          child: const Text('List installed third-party apps')),
        if (_packages.isNotEmpty) ...[
          TextField(enabled: !_busy, onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(labelText: 'Filter packages')),
          DropdownButtonFormField<String>(
            key: ValueKey('${_serial}_$_package'),
            initialValue: _package,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Select installed package'),
            items: visible.map((name) => DropdownMenuItem(value: name,
              child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: deviceReady ? (v) => setState(() {
              _package = v;
              _output = '';
            }) : null,
          ),
          OutlinedButton(onPressed: packageReady ? () => _task(() =>
              _show(() => _adb.packagePaths(_serial!, _package!))) : null,
            child: const Text('Inspect installed APK paths')),
          OutlinedButton(onPressed: packageReady ? () => _task(() =>
              _show(() => _adb.logs(_serial!, _package!))) : null,
            child: const Text('Capture selected app Logcat snapshot')),
          OutlinedButton(onPressed: packageReady ? () => _task(() =>
              _show(() => _adb.memoryInfo(_serial!, _package!))) : null,
            child: const Text('Read selected app memory report')),
          OutlinedButton(onPressed: _monitor ? () => setState(() => _monitor = false) :
              packageReady ? () => _task(_monitorLogs) : null,
            child: Text(_monitor ? 'Stop refreshing after current request' : 'Auto-refresh 10 log snapshots')),
          const Text('Logs can contain sensitive information; review before copying. '
              'Only the running main PID is requested, not all processes.'),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_output.isNotEmpty) ...[
          TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _output)),
            icon: const Icon(Icons.copy), label: const Text('Copy visible output')),
          SelectableText(_output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ]),
    );
  }
}
