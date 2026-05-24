import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../main.dart' show audioHandler;

class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final song = audioHandler.currentSong;
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]),
          boxShadow: [BoxShadow(color: Colors.pink.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(children: [
          Container(width: 48, height: 48, margin: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: song.category == MusicCategory.dj ? [Colors.orange, Colors.deepOrange] : [Colors.blue, Colors.lightBlue])), child: StreamBuilder<bool>(stream: audioHandler.player.playingStream, builder: (_, snap) => Icon(snap.data == true ? Icons.equalizer_rounded : Icons.music_note, color: Colors.white.withValues(alpha: 0.8), size: 28))),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(song.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${song.category == MusicCategory.dj ? '🔥 DJ' : '🎵 流行'} · ${audioHandler.eqPresetLabel}', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
          ])),
          StreamBuilder<bool>(stream: audioHandler.player.playingStream, builder: (_, snap) => IconButton(icon: Icon(snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white), onPressed: audioHandler.togglePlay)),
          IconButton(icon: const Icon(Icons.skip_next_rounded, color: Colors.white70), onPressed: () => audioHandler.skipToNext()),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

class CategoryHeader extends StatelessWidget {
  final MusicCategory category;
  final int count;
  const CategoryHeader({super.key, required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    final isDJ = category == MusicCategory.dj;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(gradient: LinearGradient(colors: isDJ ? [Colors.orange.shade800, Colors.deepOrange.shade700] : [Colors.blue.shade700, Colors.lightBlue.shade600])),
      child: Row(children: [
        Icon(isDJ ? Icons.bolt_rounded : Icons.headphones_rounded, color: Colors.white, size: 24),
        const SizedBox(width: 10),
        Text(isDJ ? 'DJ 劲爆' : '流行歌曲', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)), child: Text('$count 首', style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );
  }
}

class SongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  const SongTile({super.key, required this.song, required this.isPlaying, this.isFavorite = false, required this.onTap, this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: song.category == MusicCategory.dj ? [Colors.orange.shade400, Colors.deepOrange.shade300] : [Colors.blue.shade400, Colors.lightBlue.shade300])), child: Icon(isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded, color: Colors.white, size: 22)),
      title: Text(song.title, style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, color: isPlaying ? Colors.pink.shade400 : null), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        Text(song.category == MusicCategory.dj ? 'DJ' : '流行', style: TextStyle(fontSize: 12, color: isPlaying ? Colors.pink.shade300 : Colors.grey)),
        if (song.playCount > 0) ...[const SizedBox(width: 8), Icon(Icons.play_circle_outline, size: 11, color: Colors.grey.shade600), const SizedBox(width: 2), Text('${song.playCount}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600))],
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isPlaying) Icon(Icons.volume_up_rounded, color: Colors.pink.shade400, size: 20),
        if (onFavorite != null) IconButton(icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded, color: isFavorite ? Colors.amber : Colors.white30, size: 22), onPressed: onFavorite, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36)),
      ]),
    );
  }
}
