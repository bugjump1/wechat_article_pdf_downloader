import 'package:flutter/services.dart';

typedef PdfProgressCallback = void Function(double value, String message);

class NativePdfBridge {
  NativePdfBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.bugjump.wechat_article_pdf/native_pdf',
  );

  static bool _configured = false;
  static PdfProgressCallback? _progressCallback;

  static void setProgressCallback(PdfProgressCallback callback) {
    _progressCallback = callback;
    if (_configured) return;
    _configured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return null;
      final args = Map<Object?, Object?>.from(call.arguments as Map<Object?, Object?>);
      final value = ((args['value'] as num?)?.toDouble() ?? 0) / 100.0;
      final message = (args['message'] as String?) ?? '处理中';
      _progressCallback?.call(value, message);
      return null;
    });
  }

  static Future<String> renderArticleToPdf({
    required String url,
    required String outputPath,
    int waitForLazyImagesMillis = 8000,
  }) async {
    final path = await _channel.invokeMethod<String>('renderArticleToPdf', {
      'url': url,
      'outputPath': outputPath,
      'waitForLazyImagesMillis': waitForLazyImagesMillis,
    });
    if (path == null || path.isEmpty) {
      throw StateError('原生端没有返回 PDF 文件路径');
    }
    return path;
  }
}
