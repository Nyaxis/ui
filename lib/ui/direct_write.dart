import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// the gamma and the contrast that Windows draws text with, which are what the
/// edges of icons are corrected by
class TextRendering {
  const TextRendering({this.gamma = 1.8, this.grayscaleContrast = 1.0});

  final double gamma;
  final double grayscaleContrast;

  static TextRendering? _system;

  /// what the system says, which is asked once. it is the same question that
  /// Zed asks DirectWrite: the default rendering parameters, and from those the
  /// gamma and the contrast of grayscale text. without Windows, or when it
  /// does not answer, it is the usual gamma of 1.8 and a contrast of 1
  static TextRendering get system => _system ??= _ask();

  static TextRendering _ask() {
    if (!Platform.isWindows) {
      return const TextRendering();
    }
    try {
      return _askDirectWrite();
    } on Object {
      return const TextRendering();
    }
  }
}

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

typedef _CreateFactoryNative = Int32 Function(
  Int32,
  Pointer<_Guid>,
  Pointer<Pointer<Void>>,
);
typedef _CreateFactory = int Function(
  int,
  Pointer<_Guid>,
  Pointer<Pointer<Void>>,
);
typedef _OutNative = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _Out = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _QueryNative = Int32 Function(
  Pointer<Void>,
  Pointer<_Guid>,
  Pointer<Pointer<Void>>,
);
typedef _Query = int Function(
  Pointer<Void>,
  Pointer<_Guid>,
  Pointer<Pointer<Void>>,
);
typedef _ReleaseNative = Uint32 Function(Pointer<Void>);
typedef _Release = int Function(Pointer<Void>);
typedef _FloatNative = Float Function(Pointer<Void>);
typedef _Float = double Function(Pointer<Void>);

/// the function at [index] of the table of an object of COM
Pointer<NativeFunction<T>> _method<T extends Function>(
  Pointer<Void> object,
  int index,
) {
  final table = Pointer<Pointer<Void>>.fromAddress(object.cast<IntPtr>().value);
  return table[index].cast<NativeFunction<T>>();
}

void _guid(Pointer<_Guid> out, int d1, int d2, int d3, List<int> d4) {
  out.ref
    ..data1 = d1
    ..data2 = d2
    ..data3 = d3;
  for (var i = 0; i < 8; i++) {
    out.ref.data4[i] = d4[i];
  }
}

TextRendering _askDirectWrite() {
  final dwrite = DynamicLibrary.open('dwrite.dll');
  final createFactory = dwrite
      .lookupFunction<_CreateFactoryNative, _CreateFactory>(
        'DWriteCreateFactory',
      );

  final guid = calloc<_Guid>();
  final factoryOut = calloc<Pointer<Void>>();
  final paramsOut = calloc<Pointer<Void>>();
  final params1Out = calloc<Pointer<Void>>();
  try {
    // IDWriteFactory, as a shared factory (0)
    _guid(guid, 0xb859ee5a, 0xd838, 0x4b5b, [
      0xa2,
      0xe8,
      0x1a,
      0xdc,
      0x7d,
      0x93,
      0xdb,
      0x48,
    ]);
    if (createFactory(0, guid, factoryOut) != 0) {
      return const TextRendering();
    }
    final factory = factoryOut.value;

    // IDWriteFactory::CreateRenderingParams is the eighth method of the
    // interface, after the three of IUnknown
    final createParams = _method<_OutNative>(factory, 10).asFunction<_Out>();
    if (createParams(factory, paramsOut) != 0) {
      _method<_ReleaseNative>(factory, 2).asFunction<_Release>()(factory);
      return const TextRendering();
    }
    final params = paramsOut.value;

    // IDWriteRenderingParams1, which has the contrast of grayscale text
    _guid(guid, 0x94413cf4, 0xa6fc, 0x4248, [
      0x8b,
      0x50,
      0x66,
      0x74,
      0x34,
      0x8f,
      0xca,
      0xd3,
    ]);
    final query = _method<_QueryNative>(params, 0).asFunction<_Query>();
    // IDWriteRenderingParams::GetGamma is the first method after IUnknown
    final gamma = _method<_FloatNative>(params, 3).asFunction<_Float>()(params);
    var contrast = 1.0;
    if (query(params, guid, params1Out) == 0) {
      final params1 = params1Out.value;
      contrast = _method<_FloatNative>(params1, 8).asFunction<_Float>()(
        params1,
      );
      _method<_ReleaseNative>(params1, 2).asFunction<_Release>()(params1);
    }
    _method<_ReleaseNative>(params, 2).asFunction<_Release>()(params);
    _method<_ReleaseNative>(factory, 2).asFunction<_Release>()(factory);
    return TextRendering(gamma: gamma, grayscaleContrast: contrast);
  } finally {
    calloc.free(guid);
    calloc.free(factoryOut);
    calloc.free(paramsOut);
    calloc.free(params1Out);
  }
}
