import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'constants/opus_constants.dart';

typedef OpusEncoderCreateNative = Pointer Function(
    Int32 sampleRate, Int32 channels, Int32 application, Pointer<Int32> error);
typedef OpusEncoderCreate = Pointer Function(int sampleRate, int channels, int application, Pointer<Int32> error);

typedef OpusEncodeNative = Int32 Function(
    Pointer encoder, Pointer<Int16> pcm, Int32 frameSize, Pointer<Uint8> data, Int32 maxDataBytes);
typedef OpusEncode = int Function(
    Pointer encoder, Pointer<Int16> pcm, int frameSize, Pointer<Uint8> data, int maxDataBytes);

typedef OpusEncoderDestroyNative = Void Function(Pointer encoder);
typedef OpusEncoderDestroy = void Function(Pointer encoder);

typedef OpusEncoderCtlNative = Int32 Function(Pointer encoder, Int32 request, Int32 value);
typedef OpusEncoderCtl = int Function(Pointer encoder, int request, int value);

class OpusEncoder {
  static DynamicLibrary _loadOpusLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libopus.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static final DynamicLibrary _lib = _loadOpusLibrary();

  static final OpusEncoderCreate _opusEncoderCreate =
      _lib.lookup<NativeFunction<OpusEncoderCreateNative>>('opus_encoder_create').asFunction();

  static final OpusEncode _opusEncode = _lib.lookup<NativeFunction<OpusEncodeNative>>('opus_encode').asFunction();

  static final OpusEncoderDestroy _opusEncoderDestroy =
      _lib.lookup<NativeFunction<OpusEncoderDestroyNative>>('opus_encoder_destroy').asFunction();

  static final OpusEncoderCtl _opusEncoderCtl =
      _lib.lookup<NativeFunction<OpusEncoderCtlNative>>('opus_encoder_ctl').asFunction();

  Pointer? _encoder;
  final int sampleRate;
  final int channels;
  final int application;

  OpusEncoder._({
    required this.sampleRate,
    required this.channels,
    required this.application,
  });

  static OpusEncoder? create({
    required int sampleRate,
    required int channels,
    int application = 2049, // OPUS_APPLICATION_AUDIO
  }) {
    final errorPtr = malloc<Int32>();

    try {
      final encoder = _opusEncoderCreate(sampleRate, channels, application, errorPtr);
      final error = errorPtr.value;

      if (error != OPUS_OK || encoder == nullptr) {
        throw Exception('Failed to create Opus encoder, error code: $error');
      }

      final opusEncoder = OpusEncoder._(
        sampleRate: sampleRate,
        channels: channels,
        application: application,
      );
      opusEncoder._encoder = encoder;
      return opusEncoder;
    } finally {
      malloc.free(errorPtr);
    }
  }

  void setBitrate(int bitrate) {
    if (_encoder == null) throw StateError('Encoder has been disposed');
    _opusEncoderCtl(_encoder!, OPUS_SET_BITRATE_REQUEST, bitrate);
  }

  void setComplexity(int complexity) {
    if (_encoder == null) throw StateError('Encoder has been disposed');
    _opusEncoderCtl(_encoder!, OPUS_SET_COMPLEXITY_REQUEST, complexity);
  }

  Uint8List? encode(Int16List pcmData, int frameSize) {
    if (_encoder == null) throw StateError('Encoder has been disposed');

    final inputPtr = malloc<Int16>(pcmData.length);
    final maxOutputSize = 4000;
    final outputPtr = malloc<Uint8>(maxOutputSize);

    try {
      final inputList = inputPtr.asTypedList(pcmData.length);
      inputList.setAll(0, pcmData);

      final bytesEncoded = _opusEncode(_encoder!, inputPtr, frameSize, outputPtr, maxOutputSize);
      if (bytesEncoded < 0) {
        throw Exception('Opus encode failed with error: $bytesEncoded');
      }

      return outputPtr.asTypedList(bytesEncoded);
    } finally {
      malloc.free(inputPtr);
      malloc.free(outputPtr);
    }
  }

  void dispose() {
    if (_encoder != null) {
      _opusEncoderDestroy(_encoder!);
      _encoder = null;
    }
  }

  bool get isDisposed => _encoder == null;
}
