import 'package:flutter/material.dart';

import '../models/apk_report.dart';
import '../services/ai_chat_service.dart';
import '../services/google_account_service.dart';
import '../services/studio_controller.dart';
import 'binary_explorer_tabs.dart';
import 'resource_explorer_tab.dart';

class StudioShell extends StatefulWidget {
  const StudioShell({super.key, required this.controller});

  final StudioController controller;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int _tab = 0;

  static const _titles = [
    'Home',
    'Projects',
    'APK Inspector',
    'AI Studio',
    'Tools',
  ];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.folder_copy_outlined,
    Icons.code_outlined,
    Icons.auto_awesome_outlined,
    Icons.handyman_outlined,
  ];
  static const _selectedIcons = [
    Icons.dashboard,
    Icons.folder_copy,
    Icons.code,
    Icons.auto_awesome,
    Icons.handyman,
  ];

  Future<void> _import() async {
    final completed = await widget.controller.importApk();
    if (mounted && completed) setState(() => _tab = 2);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 850;
        final tabs = <Widget>[
          HomeScreen(
            controller: widget.controller,
            onImport: _import,
            openProjects: () => setState(() => _tab = 1),
            openInspector: () => setState(() => _tab = 2),
          ),
          ProjectsScreen(
            controller: widget.controller,
            onImport: _import,
            onOpen: () => setState(() => _tab = 2),
          ),
          InspectorScreen(report: widget.controller.active),
          const AiStudioScreen(),
          ToolsScreen(onImport: _import, onAnalyze: () => setState(() => _tab = 2)),
        ];
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/droidre_logo.png',
                  width: 32,
                  height: 32,
                  semanticLabel: 'DroidRE AI Studio logo',
                ),
                const SizedBox(width: 10),
                Text(wide ? 'DroidRE AI Studio' : _titles[_tab]),
              ],
            ),
            actions: [
              if (widget.controller.busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: 'Import APK',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: widget.controller.busy ? null : _import,
              ),
              IconButton(
                tooltip: 'Account and settings',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (value) => setState(() => _tab = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    _titles.length,
                    (index) => NavigationRailDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_selectedIcons[index]),
                      label: Text(_titles[index]),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (widget.controller.error != null)
                      MaterialBanner(
                        content: Text(widget.controller.error!),
                        actions: [
                          TextButton(
                            onPressed: widget.controller.clearError,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    Expanded(child: tabs[_tab]),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  height: 76,
                  onDestinationSelected: (value) => setState(() => _tab = value),
                  destinations: List.generate(
                    _titles.length,
                    (index) => NavigationDestination(
                      icon: Icon(_icons[index]),
                      selectedIcon: Icon(_selectedIcons[index]),
                      label: _titles[index] == 'APK Inspector'
                          ? 'Analyze'
                          : _titles[index],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onImport,
    required this.openProjects,
    required this.openInspector,
  });

  final StudioController controller;
  final VoidCallback onImport;
  final VoidCallback openProjects;
  final VoidCallback openInspector;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final latest = controller.active;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xff174d55), Color(0xff1b3050)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/branding/droidre_logo.png',
                width: 76,
                height: 76,
                semanticLabel: 'DroidRE AI Studio logo',
              ),
              const SizedBox(height: 14),
              const Text(
                'Explore the inside of Android apps',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Local APK inspection, manifest details, DEX inventory, '
                'native libraries and opt-in AI explanations.',
                style: TextStyle(color: Color(0xffd1e5e9), height: 1.4),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: controller.busy ? null : onImport,
                icon: const Icon(Icons.file_open),
                label: const Text('Import an APK or bundle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Workspace', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(value: '${controller.projects.length}', label: 'Projects', icon: Icons.folder),
            MetricCard(value: '${latest?.dexCount ?? 0}', label: 'DEX files', icon: Icons.data_object),
            MetricCard(value: '${latest?.nativeCount ?? 0}', label: 'Native libs', icon: Icons.memory),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent project', style: Theme.of(context).textTheme.titleLarge),
            TextButton(onPressed: openProjects, child: const Text('See all')),
          ],
        ),
        if (latest == null)
          const EmptyPanel(
            icon: Icons.inventory_2_outlined,
            title: 'No projects yet',
            description: 'Import your first APK to inspect real package data.',
          )
        else
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: color.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.android),
              ),
              title: Text(latest.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(latest.packageLabel, maxLines: 1),
              trailing: const Icon(Icons.chevron_right),
              onTap: openInspector,
            ),
          ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            StatusPill(label: 'Offline analysis', icon: Icons.shield_outlined),
            StatusPill(label: 'Read-only by default', icon: Icons.lock_outline),
            StatusPill(label: 'AI requires consent', icon: Icons.privacy_tip_outlined),
          ],
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({
    super.key,
    required this.controller,
    required this.onImport,
    required this.onOpen,
  });
  final StudioController controller;
  final VoidCallback onImport;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (controller.projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyPanel(
              icon: Icons.folder_open,
              title: 'Your workspace is empty',
              description: 'Files are copied into app-private storage for inspection.',
            ),
            FilledButton.icon(
              onPressed: controller.busy ? null : onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import APK'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: controller.projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final report = controller.projects[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.android)),
            title: Text(report.fileName),
            subtitle: Text(
              '${report.packageLabel} • ${_formatSize(report.size)} • '
              '${report.dexCount} DEX',
              maxLines: 2,
            ),
            onTap: () {
              controller.select(report);
              onOpen();
            },
            trailing: IconButton(
              tooltip: 'Remove project copy',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove local project?'),
                    content: const Text(
                      'This deletes only the imported app copy. '
                      'Your original source file is not affected.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await controller.deleteProject(report);
              },
            ),
          ),
        );
      },
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

class InspectorScreen extends StatefulWidget {
  const InspectorScreen({super.key, required this.report});
  final ApkReport? report;

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    if (report == null) {
      return const EmptyPanel(
        icon: Icons.search_off_outlined,
        title: 'Choose an APK first',
        description: 'Import a package or select a project to see analysis.',
      );
    }
    return DefaultTabController(
      key: ValueKey(report.id),
      length: 6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  report.packageLabel,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Manifest'),
              Tab(text: 'Files'),
              Tab(text: 'DEX'),
              Tab(text: 'Native'),
              Tab(text: 'Resources'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(report: report),
                _ManifestTab(info: report.manifest),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          hintText: 'Search archive paths',
                        ),
                        onChanged: (text) => setState(() => filter = text),
                      ),
                    ),
                    Expanded(
                      child: Builder(builder: (context) {
                        final matches = report.entries.where(
                          (entry) => entry.name.toLowerCase().contains(filter.toLowerCase()),
                        ).toList();
                        return ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final entry = matches[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(entry.isFile
                                  ? Icons.insert_drive_file_outlined
                                  : Icons.folder_outlined),
                              title: Text(entry.name),
                              trailing: Text(_formatSize(entry.size)),
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
                DexBrowserTab(report: report),
                ElfBrowserTab(report: report),
                ResourceExplorerTab(report: report),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.report});
  final ApkReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            MetricCard(value: '${report.entryCount}', label: 'Entries', icon: Icons.list_alt),
            MetricCard(value: '${report.dexCount}', label: 'DEX', icon: Icons.data_object),
            MetricCard(value: '${report.nativeCount}', label: 'Libraries', icon: Icons.memory),
          ],
        ),
        const SizedBox(height: 12),
        _InfoTile(label: 'File size', value: _formatSize(report.size)),
        _InfoTile(label: 'Framework indicator', value: report.framework),
        _InfoTile(label: 'Package', value: report.packageLabel),
        _InfoTile(label: 'Version', value: report.manifest.versionName),
        _InfoTile(label: 'Target SDK', value: report.manifest.targetSdk),
        _InfoTile(label: 'SHA-256', value: report.sha256),
        if (report.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Limitations and warnings', style: Theme.of(context).textTheme.titleMedium),
          for (final warning in report.warnings)
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.amber),
              title: Text(warning),
              dense: true,
            ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label, style: Theme.of(context).textTheme.labelMedium),
        subtitle: SelectableText(value.isEmpty ? 'Not available' : value),
      ),
    );
  }
}

class _ManifestTab extends StatelessWidget {
  const _ManifestTab({required this.info});
  final ManifestInfo info;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _InfoTile(label: 'Package', value: info.packageName),
        _InfoTile(label: 'Version code', value: info.versionCode),
        _InfoTile(label: 'Version name', value: info.versionName),
        _InfoTile(label: 'Minimum SDK', value: info.minSdk),
        _InfoTile(label: 'Target SDK', value: info.targetSdk),
        _SectionList(title: 'Permissions', names: info.permissions),
        _SectionList(title: 'Activities', names: info.activities),
        _SectionList(title: 'Services', names: info.services),
        _SectionList(title: 'Receivers', names: info.receivers),
        _SectionList(title: 'Providers', names: info.providers),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Android binary XML metadata is parsed locally. '
              'Resource references may require resources.arsc decoding.'),
        ),
      ],
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.title, required this.names});
  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('$title (${names.length})'),
        children: names.isEmpty
            ? [const ListTile(title: Text('None detected'))]
            : names.map((name) => ListTile(dense: true, title: SelectableText(name))).toList(),
      ),
    );
  }
}

class AiStudioScreen extends StatefulWidget {
  const AiStudioScreen({super.key});

  @override
  State<AiStudioScreen> createState() => _AiStudioScreenState();
}

class _AiStudioScreenState extends State<AiStudioScreen> {
  final keyController = TextEditingController();
  final modelController = TextEditingController(text: aiEndpoints.first.defaultModel);
  final promptController = TextEditingController();
  final service = AiChatService();
  AiEndpoint endpoint = aiEndpoints.first;
  String output = '';
  bool busy = false;

  @override
  void dispose() {
    keyController.dispose();
    modelController.dispose();
    promptController.dispose();
    service.close();
    super.dispose();
  }

  Future<void> _send() async {
    if (busy) return;
    setState(() {
      busy = true;
      output = '';
    });
    try {
      final response = await service.complete(
        endpoint: endpoint,
        model: modelController.text,
        apiKey: keyController.text,
        prompt: promptController.text,
      );
      if (mounted) setState(() => output = response);
    } catch (error) {
      if (mounted) setState(() => output = 'Request failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('AI Code Assistant', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Bring your own API key. Your APK is never uploaded by this screen. '
            'Only the prompt you explicitly type is sent to the selected provider.'),
        const SizedBox(height: 18),
        DropdownButtonFormField<AiEndpoint>(
          initialValue: endpoint,
          decoration: const InputDecoration(
            labelText: 'AI Provider',
            border: OutlineInputBorder(),
          ),
          items: aiEndpoints.map(
            (item) => DropdownMenuItem(value: item, child: Text(item.name)),
          ).toList(),
          onChanged: busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    endpoint = value;
                    modelController.text = value.defaultModel;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(endpoint.description),
        const SizedBox(height: 12),
        TextField(
          controller: modelController,
          decoration: const InputDecoration(
            labelText: 'Model ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: keyController,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'API key (session only)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.key),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: promptController,
          minLines: 4,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Ask about Android code',
            hintText: 'Paste the code or manifest snippet you want explained...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy ? null : _send,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(busy ? 'Waiting for provider...' : 'Send to selected provider'),
        ),
        const SizedBox(height: 14),
        if (output.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(output),
            ),
          ),
        const SizedBox(height: 14),
        const StatusPill(
          label: 'Automatic fallback / local RAG: later milestones',
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key, required this.onImport, required this.onAnalyze});
  final VoidCallback onImport;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    const planned = <(IconData, String, String)>[
      (Icons.account_tree_outlined, 'Smali editor', 'Native engine phase'),
      (Icons.computer, 'ELF disassembler', 'Native engine phase'),
      (Icons.compare_arrows, 'Version diff', 'Planned'),
      (Icons.fact_check_outlined, 'Security audit', 'Planned'),
      (Icons.draw_outlined, 'Rebuild and sign', 'Authorized edit phase'),
      (Icons.smart_toy_outlined, 'Local AI', 'Optional model phase'),
    ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Tools and Workflows', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.file_open),
            title: const Text('Import an APK'),
            subtitle: const Text('Working: read-only local archive and manifest analysis'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onImport,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Open APK Inspector'),
            subtitle: const Text('Working: files, permissions, DEX and .so inventory'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onAnalyze,
          ),
        ),
        const SizedBox(height: 14),
        Text('Roadmap — not implemented yet', style: Theme.of(context).textTheme.titleMedium),
        for (final tool in planned)
          Card(
            child: ListTile(
              leading: Icon(tool.$1),
              title: Text(tool.$2),
              subtitle: Text(tool.$3),
              trailing: const Icon(Icons.schedule),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${tool.$2}: ${tool.$3}')),
              ),
            ),
          ),
      ],
    );
  }
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final account = GoogleAccountService();
  String message = '';
  bool busy = false;

  Future<void> _signIn() async {
    setState(() => busy = true);
    try {
      final profile = await account.signIn();
      if (mounted) setState(() => message = 'Signed in as ${profile.email}');
    } catch (error) {
      if (mounted) setState(() => message = 'Google sign-in failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Google account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(account.configured
              ? 'Google identity sign-in is enabled. Remote backend verification '
                  'is not yet part of this local-first MVP.'
              : 'Google Sign-In is ready for OAuth configuration. '
                  'The repository owner must supply GOOGLE_WEB_CLIENT_ID.'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy || !account.configured ? null : _signIn,
            icon: const Icon(Icons.account_circle),
            label: const Text('Continue with Google'),
          ),
          if (account.account != null)
            TextButton(
              onPressed: () async {
                await account.signOut();
                if (mounted) setState(() => message = 'Signed out');
              },
              child: const Text('Sign out'),
            ),
          if (message.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message),
          ),
          const Divider(height: 36),
          Text('Privacy & capabilities', style: Theme.of(context).textTheme.titleLarge),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Local-first'),
            subtitle: Text('Your imported APK files stay on this device'),
          ),
          const ListTile(
            leading: Icon(Icons.key_off_outlined),
            title: Text('API keys are not saved'),
            subtitle: Text('AI keys exist in memory only during the current session'),
          ),
          const ListTile(
            leading: Icon(Icons.build_circle_outlined),
            title: Text('Version 0.1.0 — Foundation'),
            subtitle: Text('See docs/FEATURE_STATUS.md for engine limitations'),
          ),
        ],
      ),
    );
  }
}
