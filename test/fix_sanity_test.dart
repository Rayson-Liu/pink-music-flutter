import 'package:flutter_test/flutter_test.dart';

import 'package:pink_music_android_main/services/audio_stream.dart';
import 'package:pink_music_android_main/services/lyric_parser.dart';

void main() {
  test('selectAudioUrl: lossless prefers FLAC; auto uses standard DASH AAC', () {
    final data = {
      'dash': {
        'flac': {
          'audio': {
            'baseUrl': 'https://cd1/flac.m4s',
            'backup_url': ['https://cd2/flac.m4s'],
          }
        },
        'dolby': {'audio': null},
        'audio': [
          {
            'id': 30216,
            'bandwidth': 320000,
            'codecs': 'mp4a.40.2',
            'baseUrl': 'https://cd1/320k.m4s',
            'backupUrl': ['https://cd2/320k.m4s'],
          },
          {
            'id': 30259,
            'bandwidth': 128000,
            'codecs': 'mp4a.40.2',
            'baseUrl': 'https://cd1/128k.m4s',
          },
        ],
      }
    };
    final s1 = selectAudioUrl(data, 'lossless');
    expect(s1.label, 'FLAC');
    expect(s1.url, 'https://cd1/flac.m4s');
    expect(s1.backupUrls, ['https://cd2/flac.m4s']);
    // auto 音质不选 FLAC，走标准 DASH AAC（Android 解码兼容性）
    final s2 = selectAudioUrl(data, 'auto');
    expect(s2.label, '320K');
    expect(s2.url, 'https://cd1/320k.m4s');
    expect(s2.backupUrls, ['https://cd2/320k.m4s']);
    // 候选链：lossless 时 FLAC 优先，其余 DASH 音频降级随后
    final cands = selectAudioCandidates(data, 'lossless');
    expect(cands.map((c) => c.label).toList(),
        ['FLAC', '320K', '128K']);
  });

  test('selectAudioUrl: durl fallback collects backup urls', () {
    final data = {
      'durl': [
        {
          'url': 'https://cd1/a.mp4',
          'backup_url': ['https://cd2/a.mp4'],
        }
      ]
    };
    final s = selectAudioUrl(data, 'auto');
    expect(s.url, 'https://cd1/a.mp4');
    expect(s.backupUrls, ['https://cd2/a.mp4']);
  });

  test('LyricParser: string-form rv/tv merged with nearest match', () {
    final lrc = '[00:01.00]第一句\n[00:02.00]第二句\n';
    final rv = '[00:01.00]ichi\n[00:02.00]ni\n';
    final tv = '[00:01.05]翻译一\n[00:02.50]翻译二\n';
    final lyric = LyricParser.parseLyric({'lrc': lrc, 'rv': rv, 'tv': tv});
    expect(lyric.lines.length, 2);
    expect(lyric.lines[0].romaji, 'ichi');
    expect(lyric.lines[0].translation, '翻译一'); // ±500ms 就近匹配 1.05s
    expect(lyric.lines[1].translation, '翻译二');
  });
}
