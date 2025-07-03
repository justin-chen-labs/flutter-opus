import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'constants/opus_constants.dart';

/// -------------------- Native 类型定义 --------------------

typedef OpusDecoderCreateNative = Pointer Function(Int32 sampleRate, Int32 channels, Pointer<Int32> error);
typedef OpusDecoderCreate = Pointer Function(int sampleRate, int channels, Pointer<Int32> error);

typedef OpusDecodeNative = Int32 Function(
    Pointer decoder, Pointer<Uint8> data, Int32 len, Pointer<Int16> pcm, Int32 frameSize, Int32 decodeFec);
typedef OpusDecode = int Function(
    Pointer decoder, Pointer<Uint8> data, int len, Pointer<Int16> pcm, int frameSize, int decodeFec);

typedef OpusDecoderDestroyNative = Void Function(Pointer decoder);
typedef OpusDecoderDestroy = void Function(Pointer decoder);

typedef OpusGetVersionStringNative = Pointer<Utf8> Function();
typedef OpusGetVersionString = Pointer<Utf8> Function();

/// -------------------- OpusDecoder 类 --------------------

class OpusDecoder {
  static final DynamicLibrary _lib = _loadOpusLibrary();

  static final OpusDecoderCreate _opusDecoderCreate =
      _lib.lookup<NativeFunction<OpusDecoderCreateNative>>('opus_decoder_create').asFunction();

  static final OpusDecode _opusDecode = _lib.lookup<NativeFunction<OpusDecodeNative>>('opus_decode').asFunction();

  static final OpusDecoderDestroy _opusDecoderDestroy =
      _lib.lookup<NativeFunction<OpusDecoderDestroyNative>>('opus_decoder_destroy').asFunction();

  static final OpusGetVersionString _opusGetVersionString =
      _lib.lookup<NativeFunction<OpusGetVersionStringNative>>('opus_get_version_string').asFunction();

  Pointer? _decoder;
  final int sampleRate;
  final int channels;

  OpusDecoder._({required this.sampleRate, required this.channels});

  /// 工厂函数：创建 Opus 解码器
  static OpusDecoder? create({required int sampleRate, required int channels}) {
    final errorPtr = malloc<Int32>();
    try {
      final decoderPtr = _opusDecoderCreate(sampleRate, channels, errorPtr);
      final error = errorPtr.value;

      if (error != OPUS_OK || decoderPtr == nullptr) {
        return null;
      }

      final decoder = OpusDecoder._(sampleRate: sampleRate, channels: channels);
      decoder._decoder = decoderPtr;
      return decoder;
    } finally {
      malloc.free(errorPtr);
    }
  }

  /// 解码 Opus 数据（输出 Uint8List PCM，16-bit）
  Uint8List? decode(Uint8List opusData, int frameSize) {
    if (_decoder == null) {
      throw StateError('Decoder has been disposed');
    }

    final inputPtr = malloc<Uint8>(opusData.length);
    final outputPtr = malloc<Int16>(frameSize * channels);
    try {
      final input = inputPtr.asTypedList(opusData.length);
      input.setAll(0, opusData);

      final samplesDecoded = _opusDecode(
        _decoder!,
        inputPtr,
        opusData.length,
        outputPtr,
        frameSize,
        0, // decode_fec = false
      );

      if (samplesDecoded < 0) {
        throw Exception('Opus decode failed with error: $samplesDecoded');
      }

      final pcmBytes = Uint8List(samplesDecoded * channels * 2);
      final pcmView = outputPtr.asTypedList(samplesDecoded * channels);
      for (int i = 0; i < pcmView.length; i++) {
        final sample = pcmView[i];
        pcmBytes[i * 2] = sample & 0xFF;
        pcmBytes[i * 2 + 1] = (sample >> 8) & 0xFF;
      }

      return pcmBytes;
    } finally {
      malloc.free(inputPtr);
      malloc.free(outputPtr);
    }
  }

  /// 获取版本字符串
  static String getVersion() {
    return _opusGetVersionString().toDartString();
  }

  /// 销毁解码器
  void dispose() {
    if (_decoder != null) {
      _opusDecoderDestroy(_decoder!);
      _decoder = null;
    }
  }

  bool get isDisposed => _decoder == null;

  /// 加载 Opus 库（支持 iOS / Android）
  static DynamicLibrary _loadOpusLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libopus.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process(); // 预链接
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}
