import 'package:flutter/material.dart';
import '../services/storage_manager.dart';
import '../services/music_scanner.dart';
import '../services/online_music_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StorageManager _store;
  List<String> _scanDirs = [];
  Map<String, int> _dirCounts = {}; // 异步加载的目录歌曲数
  String _scanMode = 'quick';
  List<Map<String, String>> _musicSources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _store = await StorageManager.instance;
    _scanDirs = _store.getScanDirs();
    _scanMode = _store.scanMode;
    _musicSources = _store.getMusicSources();

    setState(() => _loading = false);

    // 异步加载目录歌曲数（不阻塞UI）
    _loadDirCounts();
  }

  Future<void> _loadDirCounts() async {
    for (final dir in _scanDirs) {
      // 用 isolate 方式异步获取
      final count = await Future.microtask(() => MusicScanner.countSongsInDir(dir));
      if (mounted) setState(() => _dirCounts[dir] = count);
    }
  }

  Future<void> _refreshSources() async {
    final sources = _store.getMusicSources();
    setState(() => _musicSources = sources);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F1A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ 设置', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A2E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFF0F0F1A),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 扫描模式 ──
          _sectionTitle('🔍 扫描设置'),
          _card([
            SwitchListTile(
              title: const Text('全局扫描模式',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              subtitle: Text(
                _scanMode == 'full' ? '扫描全部用户目录（较慢但全面）' : '仅扫描预设目录（快速）',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
              value: _scanMode == 'full',
              activeColor: Colors.pinkAccent,
              onChanged: (v) async {
                await _store.setScanMode(v ? 'full' : 'quick');
                setState(() => _scanMode = _store.scanMode);
              },
            ),
          ]),

          const SizedBox(height: 20),

          // ── 自定义目录 ──
          _sectionTitle('📁 扫描目录管理'),
          _card([
            ..._scanDirs.map((dir) => _dirItem(dir)),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.add_rounded, color: Colors.pinkAccent),
              title: const Text('添加目录', style: TextStyle(color: Colors.pinkAccent)),
              onTap: _addDir,
            ),
            if (_scanDirs.length > 2)
              ListTile(
                leading: const Icon(Icons.restore_rounded, color: Colors.orange),
                title: const Text('恢复默认目录', style: TextStyle(color: Colors.orange)),
                onTap: () async {
                  await _store.resetScanDirs();
                  setState(() {
                    _scanDirs = _store.getScanDirs();
                    _loadDirCounts();
                  });
                },
              ),
          ]),

          const SizedBox(height: 20),

          // ── 🌐 音乐源管理 ──
          _sectionTitle('🌐 在线音乐源管理'),
          _card([
            if (_musicSources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 36),
                    SizedBox(height: 8),
                    Text('暂未添加自定义源',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('默认使用内置小熊猫源搜索',
                        style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
            ..._musicSources.asMap().entries.map((e) {
              final idx = e.key;
              final src = e.value;
              return ListTile(
                leading: const Icon(Icons.cloud_done_rounded,
                    color: Colors.green, size: 22),
                title: Text(src['name'] ?? '未命名',
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(src['url'] ?? '',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 18),
                  onPressed: () async {
                    await _store.removeMusicSource(idx);
                    _refreshSources();
                  },
                ),
              );
            }),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.add_link_rounded, color: Colors.green),
              title: const Text('添加API源', style: TextStyle(color: Colors.green, fontSize: 14)),
              subtitle: const Text('输入API地址（支持{keyword}等占位符）',
                  style: TextStyle(color: Colors.white30, fontSize: 11)),
              onTap: _addSourceDialog,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 20),
              title: const Text('API格式说明', style: TextStyle(color: Colors.white54, fontSize: 13)),
              subtitle: const Text('支持占位符: {keyword} {page} {limit} {id} {quality}',
                  style: TextStyle(color: Colors.white24, fontSize: 11)),
              onTap: () => _showApiHelp(),
            ),
          ]),

          const SizedBox(height: 20),

          // ── 数据管理 ──
          _sectionTitle('💾 数据管理'),
          _card([
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              title: const Text('清除扫描缓存', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('下次启动将重新扫描'),
              onTap: () => _confirmClear(),
            ),
          ]),

          const SizedBox(height: 20),

          // ── 关于 ──
          _sectionTitle('ℹ️ 关于'),
          _card([
            const ListTile(
              leading: Icon(Icons.music_note_rounded, color: Colors.pinkAccent),
              title: Text('🦊 狸音乐 v2.1', style: TextStyle(color: Colors.white)),
              subtitle: Text('Flutter · just_audio · 小熊猫源',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  // ─────── Widget builders ───────

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(title,
        style: const TextStyle(
            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Column(children: children),
  );

  Widget _dirItem(String dir) {
    final count = _dirCounts[dir]; // null = 加载中
    return ListTile(
      leading: const Icon(Icons.folder_rounded, color: Colors.amber, size: 22),
      title: Text(dir.replaceAll('/storage/emulated/0/', ''),
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: Text(
        count == null ? '扫描中...' : '$count 首歌曲',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 18),
        onPressed: () async {
          await _store.removeScanDir(dir);
          setState(() {
            _scanDirs = _store.getScanDirs();
            _dirCounts.remove(dir);
          });
        },
      ),
    );
  }

  // ─────── Dialogs ───────

  Future<void> _addDir() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('添加目录', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: '/storage/emulated/0/你的音乐文件夹',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('添加', style: TextStyle(color: Colors.pinkAccent)),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await _store.addScanDir(result.trim());
      setState(() {
        _scanDirs = _store.getScanDirs();
        _loadDirCounts();
      });
    }
  }

  Future<void> _addSourceDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('🌐 添加API音乐源', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '源名称（如：我的小熊猫源）',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'API地址（如：https://api.xxx.com）',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '系统会自动拼接 /search /url /lyric 路径\n占位符: {keyword} {page} {limit} {id} {quality}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'name': nameCtrl.text.trim(),
              'url': urlCtrl.text.trim(),
            }),
            child: const Text('添加', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (result != null &&
        result['name']!.isNotEmpty &&
        result['url']!.isNotEmpty) {
      await _store.addMusicSource(result['name']!, result['url']!);
      _refreshSources();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已添加源: ${result['name']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showApiHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('📖 API格式说明', style: TextStyle(color: Colors.white)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HelpLine('搜索', 'GET /search?key={keyword}&page={page}&limit={limit}'),
              _HelpLine('播放', 'GET /url?id={id}&quality={quality}'),
              _HelpLine('歌词', 'GET /lyric?id={id}'),
              SizedBox(height: 12),
              Text('返回JSON格式:',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              SizedBox(height: 4),
              Text('搜索 → {"data":[{"id":"","title":"","artist":""}]}',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('播放 → {"url":"https://..."}',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              Text('歌词 → {"lyric":"[00:00.00]..."}',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              SizedBox(height: 12),
              Text('💡 只需要输入API根地址即可',
                  style: TextStyle(color: Colors.green, fontSize: 12)),
              Text('例如: https://api.xmp3.cc',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(color: Colors.pinkAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('确认清除', style: TextStyle(color: Colors.white)),
        content: const Text('将清除所有扫描缓存，下次启动重新扫描',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              await _store.clearScanCache();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('确认', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  final String label;
  final String detail;
  const _HelpLine(this.label, this.detail);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Expanded(
            child: Text(detail,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
