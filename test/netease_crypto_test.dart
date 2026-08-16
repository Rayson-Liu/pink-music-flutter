import 'package:flutter_test/flutter_test.dart';

import 'package:pink_music_android_main/services/netease_crypto.dart';

void main() {
  group('NeteaseCrypto.aesEncrypt', () {
    // 与 openssl enc -aes-128-cbc -K <ascii key hex> -iv 30313032... 对照
    test('单整块 + 补一块', () {
      expect(
        NeteaseCrypto.aesEncrypt('0123456789abcdef', '0CoJUm6Qyw8W8jud'),
        '+s1cweq9MeCjimX+ZgluybzHbmuzT4s/M590yGxxOIU=',
      );
    });

    test('非整块补丁', () {
      expect(
        NeteaseCrypto.aesEncrypt('0123456789abcde', '0CoJUm6Qyw8W8jud'),
        'Lw5NcSyTmLG7t0xDE+PPTA==',
      );
    });

    test('多字节 UTF-8 中文', () {
      expect(
        NeteaseCrypto.aesEncrypt('晴天', '0CoJUm6Qyw8W8jud'),
        'pBjHPBCgYrmoWNySxnVkjw==',
      );
    });
  });

  group('NeteaseCrypto.createSignature', () {
    test('输出包含 params 与 encSecKey 且非空', () {
      final sig = NeteaseCrypto.createSignature(
          {'s': '晴天', 'type': 1, 'limit': 5, 'offset': 0});
      expect(sig['params'], isNotNull);
      expect(sig['params']!.isNotEmpty, isTrue);
      expect(sig['encSecKey'], isNotNull);
      expect(sig['encSecKey']!.isNotEmpty, isTrue);
      // encSecKey 应为标准 base64 RSA 密文（1024 位 → 172 字符）
      expect(sig['encSecKey']!.length, greaterThanOrEqualTo(100));
    });
  });
}
