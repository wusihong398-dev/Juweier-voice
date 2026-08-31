import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JuweierVoiceApp());
}

class JuweierVoiceApp extends StatelessWidget {
  const JuweierVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '橘味儿配音',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffff6b00),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff100b0a),
        cardTheme: const CardThemeData(color: Color(0xff211814)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const HomePage(),
    );
  }
}

class ServiceState {
  final bool online;
  final String version;
  final bool vcOnline;
  final bool ffmpeg;
  final bool ffprobe;
  final bool separatorOnline;
  final bool separatorReady;
  final String gpu;
  final String qualityProfile;

  const ServiceState({
    this.online = false,
    this.version = '-',
    this.vcOnline = false,
    this.ffmpeg = false,
    this.ffprobe = false,
    this.separatorOnline = false,
    this.separatorReady = false,
    this.gpu = '-',
    this.qualityProfile = '-',
  });

  factory ServiceState.fromJson(Map<String, dynamic> data) {
    final vc = data['vc_worker'] as Map<String, dynamic>?;
    final vcData = vc?['data'] as Map<String, dynamic>?;
    final separator = data['separator'] as Map<String, dynamic>?;
    final separatorModel = data['separator_model'] as Map<String, dynamic>?;
    final quality = data['audio_quality_profile'] as Map<String, dynamic>?;
    return ServiceState(
      online: data['ok'] == true,
      version: '${data['version'] ?? '-'}',
      vcOnline: vc?['online'] == true,
      ffmpeg: data['ffmpeg'] == true,
      ffprobe: data['ffprobe'] == true,
      separatorOnline: separator?['online'] == true,
      separatorReady: separatorModel?['ready'] == true,
      gpu: '${vcData?['gpu'] ?? '-'}',
      qualityProfile: '${quality?['name'] ?? '-'}',
    );
  }
}

class ActorSlot {
  ActorSlot({required this.name, this.enabled = true});

  String name;
  bool enabled;
  PlatformFile? reference;
  String voiceId = '未绑定';
  String sourceIdentity = '等待声纹识别';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _serverKey = 'juweier_audio_server';
  int index = 0;
  String server = 'http://127.0.0.1:18115';
  String status = '未检测';
  ServiceState services = const ServiceState();
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverKey);
    if (saved != null && saved.trim().isNotEmpty) server = _normalize(saved);
    if (mounted) setState(() => initialized = true);
    await checkServer();
  }

  String _normalize(String value) => value.trim().replaceFirst(RegExp(r'/+$'), '');

  Future<void> saveServer(String value) async {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, normalized);
    if (!mounted) return;
    setState(() {
      server = normalized;
      status = '未检测';
      services = const ServiceState();
    });
    await checkServer();
  }

  Future<void> checkServer() async {
    if (!mounted) return;
    setState(() => status = '检测中…');
    try {
      final response = await http.get(Uri.parse('$server/health')).timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('健康检查格式错误');
      final state = ServiceState.fromJson(decoded);
      if (!mounted) return;
      setState(() {
        services = state;
        status = state.online ? '音频服务在线' : '服务异常';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        services = const ServiceState();
        status = '离线';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final pages = <Widget>[
      StudioPage(server: server, status: status, services: services, onCheck: checkServer),
      const InfoPage(icon: Icons.record_voice_over, title: 'AI演员库', text: '保存 Voice ID、参考声音和角色声纹。以后同一演员跨集直接复用。'),
      const InfoPage(icon: Icons.graphic_eq, title: 'AI声音设计师', text: '用于设计年龄感、性别感、共鸣、气息、情绪、口音和方言。'),
      const ProjectPage(),
      SettingsPage(server: server, status: status, services: services, onSave: saveServer, onCheck: checkServer),
    ];

    final compact = MediaQuery.sizeOf(context).width < 760;
    if (compact) {
      return Scaffold(
        body: SafeArea(child: pages[index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.auto_awesome), label: '声演'),
            NavigationDestination(icon: Icon(Icons.record_voice_over), label: '演员'),
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: '造声'),
            NavigationDestination(icon: Icon(Icons.folder_copy), label: '项目'),
            NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.auto_awesome), label: Text('声演')),
              NavigationRailDestination(icon: Icon(Icons.record_voice_over), label: Text('演员')),
              NavigationRailDestination(icon: Icon(Icons.graphic_eq), label: Text('造声')),
              NavigationRailDestination(icon: Icon(Icons.folder_copy), label: Text('项目')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('设置')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(child: pages[index])),
        ],
      ),
    );
  }
}

class StudioPage extends StatefulWidget {
  final String server;
  final String status;
  final ServiceState services;
  final VoidCallback onCheck;

  const StudioPage({super.key, required this.server, required this.status, required this.services, required this.onCheck});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final ImagePicker picker = ImagePicker();
  PlatformFile? source;
  bool running = false;
  String result = '请先导入短剧源视频，然后为需要换声的演员绑定参考声音。';
  String? outputPath;
  final List<ActorSlot> actors = [ActorSlot(name: '演员 1')];

  bool get _isWindows => Platform.isWindows;
  bool get _isAppleMobile => Platform.isIOS;
  bool get _isAndroid => Platform.isAndroid;
  bool get _isMac => Platform.isMacOS;

  String get _platformName {
    if (_isWindows) return 'Windows';
    if (_isAppleMobile) return 'iPhone / iPad';
    if (_isAndroid) return 'Android';
    if (_isMac) return 'macOS';
    return '当前设备';
  }

  Future<PlatformFile?> fromFiles() async {
    final response = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: false);
    return response?.files.single;
  }

  Future<PlatformFile?> fromGallery() async {
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return PlatformFile(name: file.name, path: file.path, size: await File(file.path).length());
  }

  Future<PlatformFile?> fromCamera() async {
    final file = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 10));
    if (file == null) return null;
    return PlatformFile(name: file.name, path: file.path, size: await File(file.path).length());
  }

  Future<PlatformFile?> addMedia(String purpose) async {
    if (_isWindows) return fromFiles();

    return showModalBottomSheet<PlatformFile>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final tiles = <Widget>[];

        if (_isAppleMobile || _isAndroid || _isMac) {
          tiles.add(ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(_isMac ? '从照片图库选择视频' : '从相册 / 图库选择视频'),
            subtitle: Text(_isAppleMobile ? '直接读取照片中的视频' : _isAndroid ? '从系统图库选择视频' : '从 macOS 照片图库选择'),
            onTap: () async {
              final media = await fromGallery();
              if (sheetContext.mounted && media != null) Navigator.pop(sheetContext, media);
            },
          ));
        }

        tiles.add(ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('从文件导入音频 / 视频'),
          subtitle: Text(_isAppleMobile ? 'iCloud Drive / 在我的 iPhone 或 iPad 上' : _isAndroid ? '设备文件 / 下载目录' : '本地文件'),
          onTap: () async {
            final media = await fromFiles();
            if (sheetContext.mounted && media != null) Navigator.pop(sheetContext, media);
          },
        ));

        if (_isAppleMobile || _isAndroid) {
          tiles.add(ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('直接拍摄视频取声'),
            subtitle: const Text('录完即可作为当前角色参考声音'),
            onTap: () async {
              final media = await fromCamera();
              if (sheetContext.mounted && media != null) Navigator.pop(sheetContext, media);
            },
          ));
          tiles.add(const ListTile(
            leading: Icon(Icons.mic),
            title: Text('App 内直接录音'),
            subtitle: Text('后续接入录音器并可直接保存到 AI 演员库'),
          ));
          tiles.add(const ListTile(
            leading: Icon(Icons.share),
            title: Text('从其他 App 分享进来'),
            subtitle: Text('后续接入系统分享扩展'),
          ));
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('添加$purpose', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('$_platformName 只显示适合当前系统的导入方式。'),
                const SizedBox(height: 14),
                ...tiles,
              ],
            ),
          ),
        );
      },
    );
  }

  String _sizeText(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).toStringAsFixed(1)} KB';

  void addActor() => setState(() => actors.add(ActorSlot(name: '演员 ${actors.length + 1}')));

  Future<void> convert() async {
    final sourcePath = source?.path;
    final activeActors = actors.where((a) => a.enabled && a.reference?.path != null).toList();
    if (sourcePath == null) {
      setState(() => result = '请先导入短剧源视频。');
      return;
    }
    if (activeActors.isEmpty) {
      setState(() => result = '至少需要为一个演员绑定参考声音。');
      return;
    }
    if (!widget.services.online || !widget.services.vcOnline || !widget.services.separatorReady) {
      setState(() => result = '音频服务尚未准备完成，请先检查 Audio / Seed-VC / Roformer 状态。');
      return;
    }

    final actor = activeActors.first;
    setState(() {
      running = true;
      outputPath = null;
      result = actors.length > 1
          ? '当前服务器接口仍为单角色完整换声，本次先处理“${actor.name}”。0.5.0 将按演员逐一锁定声纹并支持多人重叠对白。'
          : '正在处理“${actor.name}”：Roformer → Seed-VC → 背景混回 → 母带处理…';
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse('${widget.server}/api/v1/dubbing/full'));
      request.files.add(await http.MultipartFile.fromPath('media', sourcePath));
      request.files.add(await http.MultipartFile.fromPath('target', actor.reference!.path!));
      final streamed = await request.send().timeout(const Duration(minutes: 30));
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('服务器返回格式不正确');
      if (streamed.statusCode == 200 && decoded['ok'] == true) {
        final output = '${decoded['output_path'] ?? ''}';
        setState(() {
          outputPath = output.isEmpty ? null : output;
          result = '“${actor.name}”配音完成\n任务：${decoded['task_id'] ?? '-'}\n输出：${decoded['output_path'] ?? '-'}';
        });
      } else {
        setState(() => result = '配音失败：$body');
      }
    } catch (error) {
      setState(() => result = '请求失败：$error');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('橘味儿配音', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('短剧配音工作台 · 每个演员独立管理 · 音效原声保护'),
                ],
              ),
            ),
            ActionChip(
              avatar: Icon(widget.services.online ? Icons.check_circle : Icons.error_outline, size: 18),
              label: Text(widget.status),
              onPressed: widget.onCheck,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ServiceStrip(services: widget.services),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('短剧源素材', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  Chip(label: Text(_platformName)),
                ]),
                const SizedBox(height: 8),
                Text(_isWindows ? 'Windows 版只保留本地文件导入。' : '当前设备只显示适合本系统的导入入口。'),
                const SizedBox(height: 12),
                MediaButton(
                  title: source == null ? '导入短剧视频 / 音频' : source!.name,
                  subtitle: source == null ? '作为本集原始素材' : _sizeText(source!.size),
                  icon: Icons.movie,
                  enabled: !running,
                  onTap: () async {
                    final media = await addMedia('短剧源素材');
                    if (media != null) setState(() => source = media);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('演员栏目', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            OutlinedButton.icon(onPressed: running ? null : addActor, icon: const Icon(Icons.person_add), label: const Text('添加演员')),
          ],
        ),
        const SizedBox(height: 8),
        const Text('每个演员独立绑定原人物声纹和目标 Voice ID。未启用的演员保持原声。'),
        const SizedBox(height: 12),
        ...actors.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActorCard(
                slot: entry.value,
                enabled: !running,
                onChanged: () => setState(() {}),
                onPickReference: () async {
                  final media = await addMedia('${entry.value.name}参考声音');
                  if (media != null) setState(() => entry.value.reference = media);
                },
                onRemove: actors.length <= 1 ? null : () => setState(() => actors.removeAt(entry.key)),
              ),
            )),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined),
              SizedBox(width: 10),
              Expanded(child: Text('0.5.0 目标：多人同时说话也只替换被指定演员；其他人物、BGM、脚步、碰撞、环境音和原视频音效全部保持不变。')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: running ? null : convert,
          icon: running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
          label: Text(running ? '正在处理，请勿关闭…' : '开始短剧配音'),
        ),
        const SizedBox(height: 12),
        SelectableText(result),
        if (outputPath != null && Platform.isWindows) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async => Process.start('explorer.exe', [File(outputPath!).parent.path]),
            icon: const Icon(Icons.folder_open),
            label: const Text('打开输出目录'),
          ),
        ],
        const SizedBox(height: 16),
        const DevelopmentCard(),
      ],
    );
  }
}

class ActorCard extends StatelessWidget {
  final ActorSlot slot;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onPickReference;
  final VoidCallback? onRemove;

  const ActorCard({super.key, required this.slot, required this.enabled, required this.onChanged, required this.onPickReference, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Switch(value: slot.enabled, onChanged: enabled ? (v) { slot.enabled = v; onChanged(); } : null),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: slot.name,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: '演员名称', isDense: true),
                  onChanged: (v) => slot.name = v.trim().isEmpty ? slot.name : v.trim(),
                ),
              ),
              if (onRemove != null) IconButton(onPressed: enabled ? onRemove : null, icon: const Icon(Icons.delete_outline)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(avatar: const Icon(Icons.fingerprint, size: 17), label: Text(slot.sourceIdentity)),
                Chip(avatar: const Icon(Icons.badge_outlined, size: 17), label: Text('Voice ID：${slot.voiceId}')),
                OutlinedButton.icon(
                  onPressed: enabled ? onPickReference : null,
                  icon: const Icon(Icons.record_voice_over),
                  label: Text(slot.reference == null ? '绑定参考声音' : slot.reference!.name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceStrip extends StatelessWidget {
  final ServiceState services;
  const ServiceStrip({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, bool ok) => Chip(avatar: Icon(ok ? Icons.check_circle : Icons.cancel, size: 17), label: Text(text));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Audio ${services.version}', services.online),
        chip('Seed-VC', services.vcOnline),
        chip('Roformer', services.separatorOnline && services.separatorReady),
        chip('FFmpeg', services.ffmpeg),
        chip('FFprobe', services.ffprobe),
        if (services.gpu != '-') Chip(label: Text(services.gpu)),
        if (services.qualityProfile != '-') Chip(label: Text(services.qualityProfile)),
      ],
    );
  }
}

class MediaButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const MediaButton({super.key, required this.title, required this.subtitle, required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(16)),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
      ),
    );
  }
}

class DevelopmentCard extends StatelessWidget {
  const DevelopmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.video_settings),
        title: Text('AI 视频生成 · 开发测试阶段'),
        subtitle: Text('功能保留，当前产品资源优先用于音频处理和短剧配音。'),
      ),
    );
  }
}

class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        Text('项目中心', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text('项目 → 剧集 → 演员。每个演员独立保存声纹、Voice ID、参考声音和是否换声。'),
        SizedBox(height: 18),
        Card(child: ListTile(leading: Icon(Icons.folder_copy), title: Text('短剧项目'), subtitle: Text('统一管理整部短剧以及各集处理状态。'))),
        Card(child: ListTile(leading: Icon(Icons.movie_filter), title: Text('剧集'), subtitle: Text('每一集保留独立时间轴和输出版本。'))),
        Card(child: ListTile(leading: Icon(Icons.groups_2), title: Text('演员栏目'), subtitle: Text('一人一栏，跨集复用 Voice ID；未勾选演员保持原声。'))),
        Card(child: ListTile(leading: Icon(Icons.fingerprint), title: Text('0.5.0 · 目标人物锁定'), subtitle: Text('多人及重叠对白时，只替换被指定人物。'))),
        Card(child: ListTile(leading: Icon(Icons.surround_sound), title: Text('原始音效保护'), subtitle: Text('音乐、脚步、碰撞、环境声和其他演员声音保持原样。'))),
      ],
    );
  }
}

class InfoPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const InfoPage({super.key, required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [Icon(icon, size: 30), const SizedBox(width: 12), Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(text))),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String server;
  final String status;
  final ServiceState services;
  final Future<void> Function(String value) onSave;
  final VoidCallback onCheck;

  const SettingsPage({super.key, required this.server, required this.status, required this.services, required this.onSave, required this.onCheck});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController controller;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.server);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server != widget.server && controller.text != widget.server) controller.text = widget.server;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('音频服务器地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Windows 服务器本机可用 127.0.0.1:18115；手机需填写局域网或公网可访问地址。'),
              const SizedBox(height: 12),
              TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'http://127.0.0.1:18115', prefixIcon: Icon(Icons.dns))),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  onPressed: saving ? null : () async {
                    setState(() => saving = true);
                    await widget.onSave(controller.text);
                    if (mounted) setState(() => saving = false);
                  },
                  icon: const Icon(Icons.save),
                  label: Text(saving ? '保存中…' : '保存并检测'),
                ),
                OutlinedButton.icon(onPressed: widget.onCheck, icon: const Icon(Icons.refresh), label: const Text('重新检测')),
              ]),
              const SizedBox(height: 16),
              Text('状态：${widget.status}'),
              const SizedBox(height: 8),
              ServiceStrip(services: widget.services),
            ]),
          ),
        ),
      ],
    );
  }
}
