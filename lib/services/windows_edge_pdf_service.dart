import 'dart:io';

import 'native_pdf_bridge.dart';

class WindowsEdgePdfService {
  WindowsEdgePdfService._();

  static Future<void> renderUrlToPdf({
    required String url,
    required String outputPath,
    required PdfProgressCallback onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsEdgePdfService 只能在 Windows 使用');
    }

    onProgress(0.12, '正在查找 Edge / Chrome 浏览器');
    final browsers = await _findBrowserExecutables();
    if (browsers.isEmpty) {
      throw StateError('未找到 Microsoft Edge 或 Google Chrome。Windows 端需要 Chromium 浏览器的打印 PDF 能力。');
    }

    final targetFile = File(outputPath);
    final attempts = <String>[];

    for (final browser in browsers) {
      for (final headlessFlag in <String>['--headless=new', '--headless']) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        onProgress(0.28, '正在用浏览器加载网页');
        final args = <String>[
          headlessFlag,
          '--disable-gpu',
          '--hide-scrollbars',
          '--run-all-compositor-stages-before-draw',
          '--virtual-time-budget=12000',
          '--print-to-pdf-no-header',
          '--no-pdf-header-footer',
          '--print-to-pdf=$outputPath',
          url,
        ];

        final result = await Process.run(browser, args, runInShell: false);
        if (result.exitCode == 0 &&
            await targetFile.exists() &&
            await targetFile.length() > 0) {
          onProgress(1, 'PDF 已保存');
          return;
        }

        attempts.add(
          '$browser $headlessFlag => exit=${result.exitCode}, stderr=${result.stderr}',
        );
      }
    }

    throw StateError('Windows PDF 生成失败。尝试记录：${attempts.join(' | ')}');
  }

  static Future<List<String>> _findBrowserExecutables() async {
    final candidates = <String>[
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ];

    final found = <String>[];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) found.add(candidate);
    }

    for (final command in <String>['msedge', 'chrome']) {
      try {
        final where = await Process.run('where', <String>[command]);
        if (where.exitCode == 0) {
          final lines = where.stdout
              .toString()
              .split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty);
          for (final line in lines) {
            if (await File(line).exists() && !found.contains(line)) {
              found.add(line);
            }
          }
        }
      } catch (_) {
        // Ignore and continue checking other commands.
      }
    }

    return found;
  }
}
