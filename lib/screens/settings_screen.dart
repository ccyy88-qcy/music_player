import 'package:flutter/material.dart';
import '../services/storage_manager.dart';
import '../services/music_scanner.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StorageManager _store;
  List<String> _scanDirs = [];
  String _scanMode = 'quick';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _store = await StorageManager.instance;
    setState(() {
      _scanDirs = _store.getScanDirs();
      _scanMode = _store.scanMode;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                _scanMode == 'full'
                    ? '扫描全部用户目录（较慢但全面）'
                    : '仅扫描预设目录（快速）',
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
              title: const Text('添加目录',
                  style: TextStyle(color: Colors.pinkAccent)),
              onTap: _addDir,
            ),
            if (_scanDirs.length > 2)
              ListTile(
                leading: const Icon(Icons.restore_rounded, color: Colors.orange),
                title: const Text('恢复默认目录',
                    style: TextStyle(color: Colors.orange)),
                onTap: () async {
                  await _store.resetScanDirs();
                  setState(() => _scanDirs = _store.getScanDirs());
                },
              ),
          ]),

          const SizedBox(height: 20),

          // ── 数据管理 ──
          _sectionTitle('💾 数据管理'),
          _card([
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              title: const Text('清除扫描缓存',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('下次启动将重新扫描'),
              onTap: () => _confirmClear(context),
            ),
          ]),

          const SizedBox(height: 20),

          // ── 关于 ──
          _sectionTitle('ℹ️ 关于'),
          _card([
            const ListTile(
              leading: Icon(Icons.music_note_rounded, color: Colors.pinkAccent),
              title: Text('狸音乐 v2.0',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Flutter · just_audio · LRCLIB',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _dirItem(String dir) {
    final count = MusicScanner.countSongsInDir(dir);
    return ListTile(
      leading: const Icon(Icons.folder_rounded, color: Colors.amber, size: 22),
      title: Text(dir.replaceAll('/storage/emulated/0/', ''),
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: Text('$count 首歌曲',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 18),
        onPressed: () async {
          await _store.removeScanDir(dir);
          setState(() => _scanDirs = _store.getScanDirs());
        },
      ),
    );
  }

  Future<void> _addDir() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('添加目录', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: '/storage/emulated/0/你的音乐文件夹',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('添加', style: TextStyle(color: Colors.pinkAccent)),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await _store.addScanDir(result.trim());
      setState(() => _scanDirs = _store.getScanDirs());
    }
  }

  void _confirmClear(BuildContext context) {
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
              Navigator.pop(context); // 返回主页触发重新扫描
            },
            child: const Text('确认', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
