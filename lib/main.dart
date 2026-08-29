import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() => runApp(const JuweierVoiceApp());

class JuweierVoiceApp extends StatelessWidget {
  const JuweierVoiceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '橘味儿配音',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffff6b00), brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xff100b0a), cardTheme: const CardThemeData(color: Color(0xff211814))),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  String server = 'http://127.0.0.1:18110';
  String status = '未检测';
  Future<void> checkServer() async {
    setState(() => status = '检测中…');
    try {
      final r = await http.get(Uri.parse('$server/health')).timeout(const Duration(seconds: 5));
      final j = jsonDecode(r.body) as Map<String,dynamic>;
      setState(() => status = j['ok'] == true ? '在线 · ${j['gpu'] ?? 'AI Worker'}' : '异常');
    } catch (_) { setState(() => status = '离线'); }
  }
  @override Widget build(BuildContext context) {
    final pages = [
      StudioPage(server: server, status: status, onCheck: checkServer),
      const InfoPage(title:'AI演员库', text:'导入一次参考声音后保存为固定 Voice ID。以后短剧角色直接选择演员，不需要反复寻找文件。参考素材支持音频和视频。'),
      const InfoPage(title:'AI声音设计师', text:'通过性别、年龄、音高、共鸣、明亮度、沙哑度、气息、情绪、地域口音与方言等描述创建目标声音。'),
      const InfoPage(title:'项目中心', text:'统一管理短剧视频、角色、Voice ID、对白分离、Seed-VC 换声、环境声混回和导出文件。'),
      SettingsPage(server:server,status:status,onChanged:(v)=>server=v.trimRight().replaceAll(RegExp(r'/$'),''),onCheck:checkServer),
    ];
    return Scaffold(body: Row(children:[
      NavigationRail(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),labelType:NavigationRailLabelType.all,destinations:const[
        NavigationRailDestination(icon:Icon(Icons.auto_awesome),label:Text('声演')),
        NavigationRailDestination(icon:Icon(Icons.record_voice_over),label:Text('演员')),
        NavigationRailDestination(icon:Icon(Icons.graphic_eq),label:Text('造声')),
        NavigationRailDestination(icon:Icon(Icons.video_library),label:Text('项目')),
        NavigationRailDestination(icon:Icon(Icons.settings),label:Text('设置')),
      ]), const VerticalDivider(width:1), Expanded(child:pages[index])
    ]));
  }
}

class StudioPage extends StatefulWidget {
  final String server,status; final VoidCallback onCheck;
  const StudioPage({super.key,required this.server,required this.status,required this.onCheck});
  @override State<StudioPage> createState()=>_StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  PlatformFile? source,target;
  bool running=false;
  String result='请选择源音视频和目标参考音视频。';
  double similarity=.7,intelligibility=.7; int steps=20;
  final picker=ImagePicker();

  Future<PlatformFile?> fromFiles() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.any,allowMultiple:false,withData:false);
    return r?.files.single;
  }
  Future<PlatformFile?> fromPhotosVideo() async {
    final x=await picker.pickVideo(source:ImageSource.gallery);
    if(x==null) return null;
    return PlatformFile(name:x.name,path:x.path,size:await File(x.path).length());
  }
  Future<PlatformFile?> fromCameraVideo() async {
    final x=await picker.pickVideo(source:ImageSource.camera,maxDuration:const Duration(minutes:10));
    if(x==null) return null;
    return PlatformFile(name:x.name,path:x.path,size:await File(x.path).length());
  }

  Future<PlatformFile?> addMedia(String purpose) async {
    return showModalBottomSheet<PlatformFile>(context:context,isScrollControlled:true,builder:(ctx)=>SafeArea(child:Padding(
      padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('添加$purpose',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:6), const Text('iPhone 推荐直接从“照片”选择视频，软件自动把视频作为声音素材处理。'), const SizedBox(height:16),
        ListTile(leading:const Icon(Icons.photo_library),title:const Text('从相册选择视频'),subtitle:const Text('iPhone 最方便 · 无需先保存到“文件”'),onTap:() async { final f=await fromPhotosVideo(); if(ctx.mounted&&f!=null) Navigator.pop(ctx,f); }),
        ListTile(leading:const Icon(Icons.folder_open),title:const Text('从文件导入音频 / 视频'),subtitle:const Text('iCloud Drive、在我的 iPhone 上、Windows/Android 文件'),onTap:() async { final f=await fromFiles(); if(ctx.mounted&&f!=null) Navigator.pop(ctx,f); }),
        ListTile(leading:const Icon(Icons.videocam),title:const Text('直接拍摄视频取声'),subtitle:const Text('录完即可作为参考声音或源声音'),onTap:() async { final f=await fromCameraVideo(); if(ctx.mounted&&f!=null) Navigator.pop(ctx,f); }),
        const ListTile(leading:Icon(Icons.mic),title:Text('App 内直接录音'),subtitle:Text('下一阶段接入录音器；录完直接进入AI演员库')),
        const ListTile(leading:Icon(Icons.share),title:Text('从微信 / QQ / 邮件等分享进来'),subtitle:Text('下一阶段加入 iOS Share Extension，减少保存文件步骤')),
        const ListTile(leading:Icon(Icons.people_alt),title:Text('从 AI 演员库选择'),subtitle:Text('参考声音只导入一次，以后直接复用 Voice ID')),
      ]))));
  }

  Future<void> convert() async {
    if(source?.path==null||target?.path==null){setState(()=>result='请先选择源音视频和目标参考音视频。');return;}
    setState((){running=true;result='正在上传媒体并通过 Seed-VC V2 换声…';});
    try{
      final req=http.MultipartRequest('POST',Uri.parse('${widget.server}/api/v1/vc/convert'));
      req.files.add(await http.MultipartFile.fromPath('source',source!.path!)); req.files.add(await http.MultipartFile.fromPath('target',target!.path!));
      req.fields.addAll({'diffusion_steps':'$steps','length_adjust':'1.0','intelligibility_cfg_rate':intelligibility.toStringAsFixed(2),'similarity_cfg_rate':similarity.toStringAsFixed(2),'top_p':'0.9','temperature':'1.0','repetition_penalty':'1.0','convert_style':'false'});
      final s=await req.send().timeout(const Duration(minutes:10)); final body=await s.stream.bytesToString(); final d=jsonDecode(body) as Map<String,dynamic>;
      setState(()=>result=s.statusCode==200&&d['ok']==true?'换声成功\n任务：${d['task_id']}\n耗时：${d['processing_seconds']} 秒\n峰值显存：${d['peak_vram_mb']} MB\n服务器输出：${d['output_path']}':'换声失败：$body');
    }catch(e){setState(()=>result='请求失败：$e');}finally{if(mounted)setState(()=>running=false);}
  }

  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(28),children:[
    Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('橘味儿配音',style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),SizedBox(height:6),Text('Seed-VC V2 · 方言与表演保真 · 对白分离 · 环境声还原')])),ActionChip(avatar:const Icon(Icons.circle,size:12),label:Text(widget.status),onPressed:widget.onCheck)]),
    const SizedBox(height:24), const Text('导入音视频换声',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)), const SizedBox(height:10),
    Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('所有声音入口统一支持音频和视频。iPhone 可直接从相册选择视频，不必先导出声音文件。'),const SizedBox(height:16),
      Wrap(spacing:12,runSpacing:10,children:[OutlinedButton.icon(onPressed:running?null:()async{final f=await addMedia('源声音');if(f!=null)setState(()=>source=f);},icon:const Icon(Icons.add_to_photos),label:Text(source==null?'添加源媒体':'源：${source!.name}')),OutlinedButton.icon(onPressed:running?null:()async{final f=await addMedia('目标参考声音');if(f!=null)setState(()=>target=f);},icon:const Icon(Icons.person_add_alt),label:Text(target==null?'添加目标参考媒体':'目标：${target!.name}'))]),
      const SizedBox(height:18),Text('音色相似度 ${(similarity*100).round()}%'),Slider(value:similarity,min:.4,max:1,divisions:12,onChanged:running?null:(v)=>setState(()=>similarity=v)),Text('台词清晰度 ${(intelligibility*100).round()}%'),Slider(value:intelligibility,min:.4,max:1,divisions:12,onChanged:running?null:(v)=>setState(()=>intelligibility=v)),
      SegmentedButton<int>(segments:const[ButtonSegment(value:10,label:Text('快速 10步')),ButtonSegment(value:20,label:Text('标准 20步')),ButtonSegment(value:30,label:Text('精细 30步'))],selected:{steps},onSelectionChanged:running?null:(v)=>setState(()=>steps=v.first)),const SizedBox(height:18),
      FilledButton.icon(onPressed:running?null:convert,icon:running?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_awesome),label:Text(running?'正在换声…':'开始AI换声')),const SizedBox(height:14),SelectableText(result)
    ]))),
    const SizedBox(height:22),const Text('iPhone 友好导入',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:10),
    const Wrap(spacing:14,runSpacing:14,children:[Feature(icon:Icons.photo_library,title:'相册视频',text:'直接选短剧或参考视频，服务器统一提取声音。'),Feature(icon:Icons.folder_open,title:'文件',text:'继续支持 iCloud Drive 与本地音视频。'),Feature(icon:Icons.mic,title:'直接录音',text:'下一阶段加入录音后直接保存AI演员。'),Feature(icon:Icons.share,title:'系统分享',text:'下一阶段支持从其他App分享进橘味儿配音。')]),
    const SizedBox(height:22),const Text('已验证完整链路',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:10),
    const Wrap(spacing:14,runSpacing:14,children:[Feature(icon:Icons.movie_filter,title:'MP4批量换声',text:'10条批量测试成功。'),Feature(icon:Icons.spatial_audio_off,title:'Roformer对白分离',text:'对白与背景/环境/音效分离。'),Feature(icon:Icons.surround_sound,title:'环境声还原',text:'换声对白与原环境轨重新混音。'),Feature(icon:Icons.video_file,title:'原画面回写',text:'HEVC视频流直接copy，只重新编码音频。')])
  ]);
}

class Feature extends StatelessWidget{final IconData icon;final String title,text;const Feature({super.key,required this.icon,required this.title,required this.text});@override Widget build(BuildContext context)=>SizedBox(width:275,child:Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,size:30),const SizedBox(height:12),Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:7),Text(text)]))));}
class InfoPage extends StatelessWidget{final String title,text;const InfoPage({super.key,required this.title,required this.text});@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(32),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:30,fontWeight:FontWeight.bold)),const SizedBox(height:18),Card(child:Padding(padding:const EdgeInsets.all(24),child:Text(text,style:const TextStyle(fontSize:16))))]));}
class SettingsPage extends StatefulWidget{final String server,status;final ValueChanged<String> onChanged;final VoidCallback onCheck;const SettingsPage({super.key,required this.server,required this.status,required this.onChanged,required this.onCheck});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{late final TextEditingController c=TextEditingController(text:widget.server);@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(32),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('服务器设置',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),const SizedBox(height:24),TextField(controller:c,decoration:const InputDecoration(labelText:'NOVRIA Voice API 地址',hintText:'http://127.0.0.1:18110',border:OutlineInputBorder()),onChanged:widget.onChanged),const SizedBox(height:16),FilledButton.icon(onPressed:widget.onCheck,icon:const Icon(Icons.health_and_safety),label:Text('检测服务器 · ${widget.status}')),const SizedBox(height:18),Text(Platform.isIOS?'iPhone：建议优先从相册导入视频；移动端需填写服务器局域网/公网地址。':Platform.isWindows?'Windows：本机服务器可使用 127.0.0.1:18110。':'移动端：请填写运行AI服务器电脑的局域网/公网地址。')])));}
