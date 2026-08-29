import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const JuweierVoiceApp());

class JuweierVoiceApp extends StatelessWidget {
  const JuweierVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '橘味儿AI声演',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffff6b00),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff100b0a),
        cardTheme: const CardThemeData(color: Color(0xff211814)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  String server = 'http://127.0.0.1:18110';
  String status = '未检测';

  Future<void> checkServer() async {
    setState(() => status = '检测中…');
    try {
      final r = await http
          .get(Uri.parse('$server/health'))
          .timeout(const Duration(seconds: 5));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      setState(() {
        status = j['ok'] == true
            ? '在线 · ${j['gpu'] ?? 'AI Worker'}'
            : '异常';
      });
    } catch (_) {
      setState(() => status = '离线');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      StudioPage(server: server, status: status, onCheck: checkServer),
      const InfoPage(
        title: 'AI演员库',
        text: '保存固定 Voice ID，让同一角色跨片段保持同一个声音。所有参考声音入口统一支持音频和视频素材。',
      ),
      const InfoPage(
        title: 'AI声音设计师',
        text: '通过文字描述性别、年龄、音高、共鸣、明亮度、沙哑度、气息、语速、情绪、地域口音与方言特征创建目标音色。后续参考素材入口同样统一支持音视频文件。',
      ),
      const InfoPage(
        title: '项目中心',
        text: '短剧项目统一管理视频、音频、人物、Voice ID、处理状态与导出文件。所有涉及声音素材的入口统一支持音频与视频。',
      ),
      SettingsPage(
        server: server,
        status: status,
        onChanged: (v) => server = v.trimRight().replaceAll(RegExp(r'/$'), ''),
        onCheck: checkServer,
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.auto_awesome), label: Text('声演')),
              NavigationRailDestination(icon: Icon(Icons.record_voice_over), label: Text('演员')),
              NavigationRailDestination(icon: Icon(Icons.graphic_eq), label: Text('造声')),
              NavigationRailDestination(icon: Icon(Icons.video_library), label: Text('项目')),
              NavigationRailDestination(icon: Icon(Icons.settings), label: Text('设置')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[index]),
        ],
      ),
    );
  }
}

class StudioPage extends StatefulWidget {
  final String server;
  final String status;
  final VoidCallback onCheck;
  const StudioPage({super.key, required this.server, required this.status, required this.onCheck});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  PlatformFile? source;
  PlatformFile? target;
  bool running = false;
  String result = '请选择源音视频和目标参考音视频。';
  double similarity = 0.7;
  double intelligibility = 0.7;
  int steps = 20;

  Future<PlatformFile?> pickMedia() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    return r?.files.single;
  }

  Future<void> convert() async {
    if (source?.path == null || target?.path == null) {
      setState(() => result = '请先选择源音视频和目标参考音视频。');
      return;
    }
    setState(() {
      running = true;
      result = '正在上传音视频并通过 Seed-VC V2 换声…';
    });
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.server}/api/v1/vc/convert'),
      );
      req.files.add(await http.MultipartFile.fromPath('source', source!.path!));
      req.files.add(await http.MultipartFile.fromPath('target', target!.path!));
      req.fields.addAll({
        'diffusion_steps': '$steps',
        'length_adjust': '1.0',
        'intelligibility_cfg_rate': intelligibility.toStringAsFixed(2),
        'similarity_cfg_rate': similarity.toStringAsFixed(2),
        'top_p': '0.9',
        'temperature': '1.0',
        'repetition_penalty': '1.0',
        'convert_style': 'false',
      });
      final streamed = await req.send().timeout(const Duration(minutes: 10));
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (streamed.statusCode == 200 && data['ok'] == true) {
        setState(() {
          result = '换声成功\n任务：${data['task_id']}\n耗时：${data['processing_seconds']} 秒\n峰值显存：${data['peak_vram_mb']} MB\n服务器输出：${data['output_path']}';
        });
      } else {
        setState(() => result = '换声失败：$body');
      }
    } catch (e) {
      setState(() => result = '请求失败：$e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('橘味儿AI声演', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Seed-VC V2 · 方言与表演保真 · 对白分离 · 环境声还原'),
                ],
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.circle, size: 12),
              label: Text(widget.status),
              onPressed: widget.onCheck,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('已接入测试功能', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导入音视频换声', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('源文件和目标参考文件均支持音频或视频。前端不限制扩展名，统一作为媒体素材导入。'),
                const SizedBox(height: 8),
                const Text('常见格式：MP4 / MOV / MKV / AVI / WEBM / M4V / MPEG / MPG / TS / MTS / M2TS / WMV / FLV，以及 WAV / MP3 / FLAC / M4A / AAC / OGG / OPUS / WMA / AIFF / APE 等。', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: running ? null : () async {
                        final f = await pickMedia();
                        if (f != null) setState(() => source = f);
                      },
                      icon: const Icon(Icons.perm_media),
                      label: Text(source == null ? '选择源音视频' : '源：${source!.name}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: running ? null : () async {
                        final f = await pickMedia();
                        if (f != null) setState(() => target = f);
                      },
                      icon: const Icon(Icons.video_audio_call),
                      label: Text(target == null ? '选择目标参考音视频' : '目标：${target!.name}'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('音色相似度 ${(similarity * 100).round()}%'),
                Slider(value: similarity, min: 0.4, max: 1.0, divisions: 12, onChanged: running ? null : (v) => setState(() => similarity = v)),
                Text('台词清晰度 ${(intelligibility * 100).round()}%'),
                Slider(value: intelligibility, min: 0.4, max: 1.0, divisions: 12, onChanged: running ? null : (v) => setState(() => intelligibility = v)),
                Row(
                  children: [
                    const Text('质量：'),
                    const SizedBox(width: 10),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 10, label: Text('快速 10步')),
                        ButtonSegment(value: 20, label: Text('标准 20步')),
                        ButtonSegment(value: 30, label: Text('精细 30步')),
                      ],
                      selected: {steps},
                      onSelectionChanged: running ? null : (v) => setState(() => steps = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: running ? null : convert,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(running ? '正在换声…' : '开始AI换声'),
                ),
                const SizedBox(height: 16),
                SelectableText(result),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text('统一媒体兼容规则', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('软件内所有涉及“声音素材”的功能统一支持音频文件和视频文件，包括：源声音、目标参考声音、AI演员参考素材、方言投稿、声音克隆、短剧角色绑定、对白分离、批量换声和声音设计参考素材。\n\n前端不再按扩展名限制用户；服务端统一使用 FFmpeg / 音频解码链路提取可处理音轨。'),
          ),
        ),
        const SizedBox(height: 22),
        const Text('已验证完整链路', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            Feature(icon: Icons.movie_filter, title: 'MP4 批量换声', text: '10条批量测试成功，支持断点续跑。'),
            Feature(icon: Icons.spatial_audio_off, title: 'Roformer 对白分离', text: '分离人物对白与 Other 背景/环境/音效轨。'),
            Feature(icon: Icons.surround_sound, title: '环境声还原', text: '换声对白与原环境轨重新混音。'),
            Feature(icon: Icons.video_file, title: 'MP4 无损画面回写', text: '原 HEVC 视频流直接 copy，只重新编码音频。'),
          ],
        ),
      ],
    );
  }
}

class Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const Feature({super.key, required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 275,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 7),
                Text(text),
              ],
            ),
          ),
        ),
      );
}

class InfoPage extends StatelessWidget {
  final String title;
  final String text;
  const InfoPage({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Card(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, style: const TextStyle(fontSize: 16)))),
          ],
        ),
      );
}

class SettingsPage extends StatefulWidget {
  final String server;
  final String status;
  final ValueChanged<String> onChanged;
  final VoidCallback onCheck;
  const SettingsPage({super.key, required this.server, required this.status, required this.onChanged, required this.onCheck});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController c = TextEditingController(text: widget.server);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('服务器设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: c,
              decoration: const InputDecoration(labelText: 'NOVRIA Voice API 地址', hintText: 'http://127.0.0.1:18110', border: OutlineInputBorder()),
              onChanged: widget.onChanged,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: widget.onCheck, icon: const Icon(Icons.health_and_safety), label: Text('检测服务器 · ${widget.status}')),
            const SizedBox(height: 18),
            Text(Platform.isWindows ? '当前平台：Windows · 本机服务器可使用 127.0.0.1。' : '移动端请填写运行 NOVRIA Voice Server 的电脑局域网或公网地址。'),
          ],
        ),
      );
}
