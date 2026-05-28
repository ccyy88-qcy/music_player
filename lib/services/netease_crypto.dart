import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:crypto/crypto.dart';

/// 网易云EAPI加密密钥
const _eapiKey = 'e82ckenh8dichen8';

/// AES-128-ECB加密
Uint8List _aesEcbEncrypt(Uint8List data, Uint8List key) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(key), Uint8List(16))); // ECB用空IV
  // ECB模式：手动分块
  final blockSize = 16;
  final padded = _pkcs7Pad(data, blockSize);
  final output = Uint8List(padded.length);
  var offset = 0;
  final temp = Uint8List(blockSize);
  while (offset < padded.length) {
    temp.setRange(0, blockSize, padded.sublist(offset, offset + blockSize));
    cipher.processBlock(temp, 0, output, offset);
    offset += blockSize;
  }
  return output;
}

/// ECB mode (no IV)
class _ECBBlockCipher extends BlockCipher {
  final AESEngine _engine = AESEngine();
  bool _encrypt = false;

  @override
  String get algorithmName => 'AES/ECB';

  @override
  int get blockSize => 16;

  @override
  void init(bool encrypt, CipherParameters? params) {
    _encrypt = encrypt;
    if (params is KeyParameter) {
      _engine.init(encrypt, params);
    } else if (params is ParametersWithIV) {
      _engine.init(encrypt, KeyParameter(params.key));
    } else {
      throw ArgumentError('Invalid params');
    }
  }

  @override
  int processBlock(Uint8List inp, int inpOff, Uint8List out, int outOff) {
    return _engine.processBlock(inp, inpOff, out, outOff);
  }

  @override
  void reset() => _engine.reset();
}

Uint8List _aesEcb(Uint8List data, Uint8List key) {
  final cipher = _ECBBlockCipher();
  cipher.init(true, KeyParameter(key));
  final padded = _pkcs7Pad(data, cipher.blockSize);
  final output = Uint8List(padded.length);
  var offset = 0;
  while (offset < padded.length) {
    final len = cipher.processBlock(padded, offset, output, offset);
    offset += len;
  }
  return output;
}

Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
  final padLen = blockSize - (data.length % blockSize);
  final padded = Uint8List(data.length + padLen);
  padded.setRange(0, data.length, data);
  for (int i = 0; i < padLen; i++) {
    padded[data.length + i] = padLen;
  }
  return padded;
}

/// EAPI加密
/// url: API路径 (如 /api/song/enhance/player/url/v1)
/// text: 要加密的内容 (JSON字符串)
/// 返回: base64编码的加密参数
String eapiEncrypt(String url, String text) {
  final digest = md5.convert(utf8.encode('nobody${url}use${text}md5forencrypt')).toString();
  final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';
  final encrypted = _aesEcb(utf8.encode(data), utf8.encode(_eapiKey));
  return base64.encode(encrypted);
}
