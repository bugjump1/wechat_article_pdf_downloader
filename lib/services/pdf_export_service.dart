import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'native_pdf_bridge.dart';
import 'windows_edge_pdf_service.dart';

enum PdfExportAction { shared, saved, cancelled }

class PdfExportResult {
  const PdfExportResult({
    required this.action,
    required this.path,
    required this.fileName,
  });

  final PdfExportAction action;
  final String path;
  final String fileName;
}

class PdfExportService {
  PdfExportService._();

  static Future<PdfExportResult> exportWeChatArticle({
    required String url,
    required PdfProgressCallback onProgress,
  }) async {
    final fileName = _fileName();

    if (Platform.isAndroid || Platform.isIOS) {
      return _exportAndShareOnMobile(
        url: url,
        fileName: fileName,
        onProgress: onProgress,
      );
    }

    if (Platform.isWindows) {
      return _exportAndSaveOnWindows(
        url: url,
        fileName: fileName,
        onProgress: onProgress,
      );
    }

    throw UnsupportedError('当前只适配 Android、iOS 和 Windows');
  }

  static Future<PdfExportResult> _exportAndShareOnMobile({
    required String url,
    required String fileName,
    required PdfProgressCallback onProgress,
  }) async {
    NativePdfBridge.setProgressCallback(onProgress);

    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}${Platform.pathSeparator}$fileName';

    onProgress(0.05, '正在打开微信公众号文章');
    final generatedPath = await NativePdfBridge.renderArticleToPdf(
      url: url,
      outputPath: outputPath,
    );

    onProgress(0.95, '正在打开系统分享面板');
    await SharePlus.instance.share(
      ShareParams(
        title: '微信公众号推文 PDF',
        text: '微信公众号推文 PDF',
        files: <XFile>[
          XFile(
            generatedPath,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
      ),
    );

    onProgress(1, '完成');
    return PdfExportResult(
      action: PdfExportAction.shared,
      path: generatedPath,
      fileName: fileName,
    );
  }

  static Future<PdfExportResult> _exportAndSaveOnWindows({
    required String url,
    required String fileName,
    required PdfProgressCallback onProgress,
  }) async {
    onProgress(0.05, '请选择保存位置');
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'PDF 文件',
          extensions: <String>['pdf'],
          mimeTypes: <String>['application/pdf'],
        ),
      ],
    );

    if (location == null) {
      return PdfExportResult(
        action: PdfExportAction.cancelled,
        path: '',
        fileName: fileName,
      );
    }

    final outputPath = location.path.toLowerCase().endsWith('.pdf')
        ? location.path
        : '${location.path}.pdf';

    await WindowsEdgePdfService.renderUrlToPdf(
      url: url,
      outputPath: outputPath,
      onProgress: onProgress,
    );

    return PdfExportResult(
      action: PdfExportAction.saved,
      path: outputPath,
      fileName: outputPath.split(Platform.pathSeparator).last,
    );
  }

  static String _fileName() {
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'wechat_article_$stamp.pdf';
  }
}
