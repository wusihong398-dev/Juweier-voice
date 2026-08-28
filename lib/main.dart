import 'dart:convert';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffff6b00), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xff100b0a),
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
      final r = await http.get(Uri.parse('$server/health')).timeout(const Duration(seconds: 5));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      setState(() => status = j['ok'] == true ? '在线 · ${j['gpu'] ?? 'AI Worker'}' : '异常');
    } catch (_) {
      setState(() => status = '离线');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Studio(onCheck: checkServer, status: status),
      const _SimplePage(title: 'AI演员库', text: '保存固定 Voice ID，让同一角色跨片段保持同一个声音。'),
      const _SimplePage(title: 'AI声音设计师', text: '通过文字描述性别、年龄、音高、质感、情绪、方言、气息与表演风格，生成目标音色。'),
      const _SimplePage(title: '项目中心', text: '管理整集短剧、人物、批量片段、处理进度与最终导出。'),
      _Settings(server: server, status: status, onChanged: (v) => server = v, onCheck: checkServer),
    ];
    return Scaffold(
      body: Row(children: [
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
      ]),
    );
  }
}

class _Studio extends StatelessWidget {
  final VoidCallback onCheck;
  final String status;
  const _Studio({required this.onCheck, required this.status});
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(28), children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('橘味儿AI声演', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('角色统一 · 方言保真 · 环境声还原 · 批量短剧换声'),
        ])),
        ActionChip(avatar: const Icon(Icons.circle, size: 12), label: Text(status), onPressed: onCheck),
      ]),
      const SizedBox(height: 28),
      Wrap(spacing: 16, runSpacing: 16, children: const [
        _Feature(icon: Icons.movie_filter, title: 'AI短剧配音', text: '批量导入 MP4，统一角色声音并保留环境声。'),
        _Feature(icon: Icons.swap_horiz, title: '导入语音换声', text: '支持音视频输入，自动提取音频并完成角色换声。'),
        _Feature(icon: Icons.spatial_audio_off, title: '对白分离', text: 'Roformer 分离对白与 BGM / 环境声 / 音效。'),
        _Feature(icon: Icons.psychology, title: 'AI声音设计', text: '通过自然语言描述创建新的目标音色。'),
      ]),
      const SizedBox(height: 30),
      const Text('快速工作流', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('导入视频  →  识别/分离对白  →  选择AI演员  →  Seed-VC换声  →  环境声混回  →  导出MP4'))),
    ]);
  }
}

class _Feature extends StatelessWidget {
  final IconData icon; final String title; final String text;
  const _Feature({required this.icon, required this.title, required this.text});
  @override
  Widget build(BuildContext context) => SizedBox(width: 300, child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 32), const SizedBox(height: 14), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(text)]))));
}

class _SimplePage extends StatelessWidget {
  final String title; final String text;
  const _SimplePage({required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)), const SizedBox(height: 18), Card(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, style: const TextStyle(fontSize: 16))))]));
}

class _Settings extends StatefulWidget {
  final String server; final String status; final ValueChanged<String> onChanged; final VoidCallback onCheck;
  const _Settings({required this.server, required this.status, required this.onChanged, required this.onCheck});
  @override State<_Settings> createState() => _SettingsState();
}
class _SettingsState extends State<_Settings> {
  late final TextEditingController c = TextEditingController(text: widget.server);
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('服务器设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)), const SizedBox(height: 24), TextField(controller: c, decoration: const InputDecoration(labelText: 'NOVRIA Voice API 地址', border: OutlineInputBorder()), onChanged: widget.onChanged), const SizedBox(height: 16), FilledButton.icon(onPressed: widget.onCheck, icon: const Icon(Icons.health_and_safety), label: Text('检测服务器 · ${widget.status}'))]));
}
