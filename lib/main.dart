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
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_serverKey);
    if (saved != null && saved.trim().isNotEmpty) {
      server = _normalizeServer(saved);
    }
    if (mounted) setState(() => initialized = true);
    await checkServer();
  }

  String _normalizeServer(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> saveServer(String value) async {
    final normalized = _normalizeServer(value);
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
      final response = await http
          .get(Uri.parse('$server/health'))
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('健康检查返回格式不正确');
      }
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
    if (!initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = <Widget>[
      StudioPage(
        server: server,
        status: status,
        services: services,
        onCheck: checkServer,
      ),
      const InfoPage(
        icon: Icons.record_voice_over,
        title: 'AI演员库',
        text: '把通过审核的参考声音保存为 Voice ID，后续项目直接复用。下一阶段会加入多人角色、声纹绑定和目标人物锁定。',
      ),
      const InfoPage(
        icon: Icons.graphic_eq,
        title: 'AI声音设计师',
        text: '用于创建或微调年龄感、性别感、音高、共鸣、气息、情绪和地域口音。正式输出会优先保证台词可懂度和自然度。',
      ),
      const ProjectPage(),
      SettingsPage(
        server: server,
        status: status,
        services: services,
        onSave: saveServer,
        onCheck: checkServer,
      ),
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
              NavigationRailDestination(
                icon: Icon(Icons.auto_awesome),
                label: Text('声演'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.record_voice_over),
                label: Text('演员'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.graphic_eq),
                label: Text('造声'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_copy),
                label: Text('项目'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('设置'),
              ),
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

  const StudioPage({
    super.key,
    required this.server,
    required this.status,
    required this.services,
    required this.onCheck,
  });

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  PlatformFile? source;
  PlatformFile? target;
  bool running = false;
  String result = '请选择源音视频和目标参考音视频。';
  String? outputPath;
  String? taskId;
  final ImagePicker picker = ImagePicker();

  Future<PlatformFile?> fromFiles() async {
    final response = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    return response?.files.single;
  }

  Future<PlatformFile?> fromPhotosVideo() async {
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return PlatformFile(
      name: file.name,
      path: file.path,
      size: await File(file.path).length(),
    );
  }

  Future<PlatformFile?> fromCameraVideo() async {
    final file = await picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 10),
    );
    if (file == null) return null;
    return PlatformFile(
      name: file.name,
      path: file.path,
      size: await File(file.path).length(),
    );
  }

  Future<PlatformFile?> addMedia(String purpose) async {
    return showModalBottomSheet<PlatformFile>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '添加$purpose',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text('音频和视频都可以直接作为素材；视频会在服务器端自动提取音轨。'),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('从相册选择视频'),
                  subtitle: const Text('适合 iPhone / Android'),
                  onTap: () async {
                    final media = await fromPhotosVideo();
                    if (sheetContext.mounted && media != null) {
                      Navigator.pop(sheetContext, media);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('从文件导入音频 / 视频'),
                  subtitle: const Text('Windows、Android、iCloud Drive 等'),
                  onTap: () async {
                    final media = await fromFiles();
                    if (sheetContext.mounted && media != null) {
                      Navigator.pop(sheetContext, media);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam),
                  title: const Text('直接拍摄视频取声'),
                  subtitle: const Text('录完即可作为参考声音'),
                  onTap: () async {
                    final media = await fromCameraVideo();
                    if (sheetContext.mounted && media != null) {
                      Navigator.pop(sheetContext, media);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _sizeText(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> convert() async {
    final sourcePath = source?.path;
    final targetPath = target?.path;
    if (sourcePath == null || targetPath == null) {
      setState(() => result = '请先选择源音视频和目标参考音视频。');
      return;
    }
    if (!widget.services.online) {
      setState(() => result = '18115 音频服务当前离线，请先在“设置”中检查服务器。');
      return;
    }
    if (!widget.services.vcOnline) {
      setState(() => result = 'Seed-VC Worker 当前离线，无法开始换声。');
      return;
    }
    if (!widget.services.separatorReady) {
      setState(() => result = 'Roformer 分离模型当前不可用，无法开始完整配音。');
      return;
    }

    setState(() {
      running = true;
      taskId = null;
      outputPath = null;
      result = '正在执行高清配音：音轨分析 → Roformer 分离 → Seed-VC → 背景混回 → 母带处理…';
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.server}/api/v1/dubbing/full'),
      );
      request.files.add(await http.MultipartFile.fromPath('media', sourcePath));
      request.files.add(await http.MultipartFile.fromPath('target', targetPath));

      final streamed = await request.send().timeout(const Duration(minutes: 30));
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('服务器返回格式不正确');
      }

      if (streamed.statusCode == 200 && decoded['ok'] == true) {
        final vc = decoded['vc'] as Map<String, dynamic>?;
        final mix = decoded['mix'] as Map<String, dynamic>?;
        final seconds = vc?['processing_seconds'];
        final vram = vc?['peak_vram_mb'];
        final output = '${decoded['output_path'] ?? ''}';
        setState(() {
          taskId = '${decoded['task_id'] ?? ''}';
          outputPath = output.isEmpty ? null : output;
          result = '高清配音完成\n'
              '模式：${decoded['mode'] ?? 'full_dubbing_hq'}\n'
              '任务：${decoded['task_id'] ?? '-'}\n'
              'Seed-VC：${seconds ?? '-'} 秒 · 峰值显存 ${vram ?? '-'} MB\n'
              '母带：${mix?['target_lufs'] ?? '-'} LUFS / ${mix?['true_peak_db'] ?? '-'} dBTP\n'
              '输出：${decoded['output_path'] ?? '-'}';
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
                  Text(
                    '橘味儿配音',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text('前期专注音频处理与短剧配音 · Seed-VC V2 + BS-Roformer'),
                ],
              ),
            ),
            ActionChip(
              avatar: Icon(
                widget.services.online ? Icons.check_circle : Icons.error_outline,
                size: 18,
              ),
              label: Text(widget.status),
              onPressed: widget.onCheck,
            ),
          ],
        ),
        const SizedBox(height: 18),
        ServiceStrip(services: widget.services),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.record_voice_over),
                    SizedBox(width: 10),
                    Text(
                      '短剧高清换声',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('当前使用完整音频链路，不再直接把整条视频音轨送入 Seed-VC。'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    MediaButton(
                      title: source == null ? '添加源视频 / 音频' : source!.name,
                      subtitle: source == null ? '需要替换对白的素材' : _sizeText(source!.size),
                      icon: Icons.movie,
                      enabled: !running,
                      onTap: () async {
                        final media = await addMedia('源素材');
                        if (media != null) setState(() => source = media);
                      },
                    ),
                    MediaButton(
                      title: target == null ? '添加参考声音' : target!.name,
                      subtitle: target == null ? '目标人物的音色参考' : _sizeText(target!.size),
                      icon: Icons.person_search,
                      enabled: !running,
                      onTap: () async {
                        final media = await addMedia('目标参考声音');
                        if (media != null) setState(() => target = media);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '目标人物锁定模式正在升级到 0.5.0：最终目标是多人同时说话时，也只替换指定人物，其他人物、音乐、脚步、碰撞和环境音保持原样。',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: running ? null : convert,
                  icon: running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(running ? '正在处理，请勿关闭…' : '开始高清配音'),
                ),
                const SizedBox(height: 14),
                SelectableText(result),
                if (taskId != null) ...[
                  const SizedBox(height: 8),
                  Text('任务 ID：$taskId', style: Theme.of(context).textTheme.bodySmall),
                ],
                if (outputPath != null && Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final path = outputPath!;
                      final parent = File(path).parent.path;
                      await Process.start('explorer.exe', [parent]);
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('打开输出目录'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const DevelopmentCard(),
      ],
    );
  }
}

class ServiceStrip extends StatelessWidget {
  final ServiceState services;

  const ServiceStrip({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('Audio ${services.version}', services.online),
        _chip('Seed-VC', services.vcOnline),
        _chip('Roformer', services.separatorOnline && services.separatorReady),
        _chip('FFmpeg', services.ffmpeg),
        _chip('FFprobe', services.ffprobe),
        if (services.gpu != '-') Chip(label: Text(services.gpu)),
        if (services.qualityProfile != '-') Chip(label: Text(services.qualityProfile)),
      ],
    );
  }

  Widget _chip(String text, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel, size: 17),
      label: Text(text),
    );
  }
}

class MediaButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const MediaButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(16),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DevelopmentCard extends StatelessWidget {
  const DevelopmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.video_settings),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI 视频生成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 4),
                  const Text('功能保留，但当前处于开发测试阶段。前期产品资源优先用于音频处理、换声和短剧配音。'),
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.science, size: 17),
                    label: const Text('开发测试阶段'),
                    backgroundColor: Colors.orange.withValues(alpha: 0.12),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        Text('后续用于管理短剧、角色、Voice ID、目标人物声纹、处理任务和导出版本。'),
        SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: Icon(Icons.person_pin_circle),
            title: Text('0.5.0 · 目标人物锁定'),
            subtitle: Text('多人和重叠对白场景下，仅替换指定人物的声音。'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.surround_sound),
            title: Text('原始音效保护'),
            subtitle: Text('目标人物之外的对白、BGM、脚步、碰撞、环境声保持原音。'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.fingerprint),
            title: Text('Voice ID / 声纹绑定'),
            subtitle: Text('参考声音只录入一次，后续自动识别并锁定对应角色。'),
          ),
        ),
      ],
    );
  }
}

class InfoPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const InfoPage({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(text),
          ),
        ),
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

  const SettingsPage({
    super.key,
    required this.server,
    required this.status,
    required this.services,
    required this.onSave,
    required this.onCheck,
  });

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
    if (oldWidget.server != widget.server && controller.text != widget.server) {
      controller.text = widget.server;
    }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('音频服务器地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Windows 服务器本机可用 127.0.0.1:18115；手机需要填写服务器局域网或公网可访问地址。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'http://127.0.0.1:18115',
                    prefixIcon: Icon(Icons.dns),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              setState(() => saving = true);
                              await widget.onSave(controller.text);
                              if (mounted) setState(() => saving = false);
                            },
                      icon: const Icon(Icons.save),
                      label: Text(saving ? '保存中…' : '保存并检测'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onCheck,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新检测'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('状态：${widget.status}'),
                const SizedBox(height: 8),
                ServiceStrip(services: widget.services),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
