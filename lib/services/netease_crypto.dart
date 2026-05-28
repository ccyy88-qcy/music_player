import 'dart:typed_data';
import 'dart:convert';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

/// 网易云EAPI加密密钥
const _eapiKey = 'e82ckenh8dichen8';

/// AES-128-ECB加密，返回HEX大写字符串（非base64！）
String _aesEcbEncrypt(String plainText, String key) {
  final keyBytes = utf8.encode(key);
  final data = utf8.encode(plainText);

  // PKCS7 padding
  final blockSize = 16;
  final padLen = blockSize - (data.length % blockSize);
  final padded = Uint8List(data.length + padLen);
  padded.setRange(0, data.length, data);
  for (int i = 0; i < padLen; i++) {
    padded[data.length + i] = padLen;
  }

  final cipher = ECBBlockCipher(AESEngine());
  cipher.init(true, KeyParameter(keyBytes));

  final output = Uint8List(padded.length);
  for (int i = 0; i < padded.length; i += blockSize) {
    cipher.processBlock(padded, i, output, i);
  }

  // EAPI用HEX编码（大写），不是base64！
  return output.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
}

/// EAPI加密
/// [path] API路径 (如 /api/song/enhance/player/url/v1)
/// [body] JSON请求体字符串
/// 返回: HEX编码的加密params
String eapiEncrypt(String path, String body) {
  final digest = md5.convert(utf8.encode('nobody${path}use${body}md5forencrypt')).toString();
  final data = '$path-36cd479b6b5-$body-36cd479b6b5-$digest';
  return _aesEcbEncrypt(data, _eapiKey);
}
