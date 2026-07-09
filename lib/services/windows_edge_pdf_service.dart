import 'dart:convert';
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

    final printablePage = await _preparePrintablePage(
      url: url,
      onProgress: onProgress,
    );
    final profileDir = await Directory.systemTemp.createTemp('wechat_pdf_profile_');
    final targetFile = File(outputPath);
    final attempts = <String>[];

    try {
      for (final browser in browsers) {
        for (final headlessFlag in <String>['--headless=new', '--headless']) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          onProgress(0.36, '正在用浏览器生成 PDF');
          final args = <String>[
            headlessFlag,
            '--disable-gpu',
            '--disable-extensions',
            '--disable-component-extensions-with-background-pages',
            '--no-first-run',
            '--no-default-browser-check',
            '--hide-scrollbars',
            '--run-all-compositor-stages-before-draw',
            '--virtual-time-budget=45000',
            '--user-data-dir=${profileDir.path}',
            '--print-to-pdf-no-header',
            '--no-pdf-header-footer',
            '--print-to-pdf=$outputPath',
            printablePage.uri,
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
    } finally {
      await printablePage.cleanup();
      await profileDir.delete(recursive: true).catchError((_) => profileDir);
    }

    throw StateError('Windows PDF 生成失败。尝试记录：${attempts.join(' | ')}');
  }

  static Future<_PrintablePage> _preparePrintablePage({
    required String url,
    required PdfProgressCallback onProgress,
  }) async {
    onProgress(0.18, '正在预处理微信图片');
    final sourceUri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = _wechatMobileUserAgent;

    try {
      final request = await client.getUrl(sourceUri);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw StateError('网页请求失败：HTTP ${response.statusCode}');
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }

      final html = const Utf8Decoder(allowMalformed: true).convert(bytes);
      final printableHtml = _injectPrintHelpers(html, sourceUri);
      final tempDir = await Directory.systemTemp.createTemp('wechat_pdf_html_');
      final htmlFile = File('${tempDir.path}${Platform.pathSeparator}article.html');
      await htmlFile.writeAsString(printableHtml, encoding: utf8);
      return _PrintablePage(uri: htmlFile.uri.toString(), tempDir: tempDir);
    } finally {
      client.close(force: true);
    }
  }

  static String _injectPrintHelpers(String html, Uri sourceUri) {
    final baseHref = const HtmlEscape().convert(sourceUri.toString());
    final cleanedHtml = html.replaceAll(
      RegExp(
        r'''<meta[^>]+http-equiv=["']Content-Security-Policy["'][^>]*>''',
        caseSensitive: false,
      ),
      '',
    );
    final headPatch = '''
<base href="$baseHref">
<style>
  img { max-width: 100% !important; height: auto !important; }
  @media print {
    body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    img { max-width: 100% !important; height: auto !important; }
  }
</style>
''';
    const bodyPatch = r'''
<script>
(function() {
  function upgradeImages() {
    document.querySelectorAll('img').forEach(function(img) {
      var src = img.getAttribute('data-src') ||
        img.getAttribute('data-original') ||
        img.getAttribute('data-backsrc') ||
        img.getAttribute('data-wxsrc') ||
        img.getAttribute('data-ratio-src');
      var current = img.getAttribute('src') || '';
      if (src && (!current || current.indexOf('data:') === 0 || current.indexOf('loading') >= 0)) {
        img.setAttribute('src', src.replace(/^http:/, 'https:'));
      }
      img.removeAttribute('loading');
      img.style.maxWidth = '100%';
      img.style.height = 'auto';
    });
  }

  function scrollThroughPage(step) {
    var height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
    window.scrollTo(0, Math.floor(height * step / 10));
    upgradeImages();
    if (step < 10) {
      setTimeout(function() { scrollThroughPage(step + 1); }, 600);
    } else {
      window.scrollTo(0, 0);
      upgradeImages();
    }
  }

  upgradeImages();
  window.addEventListener('load', function() {
    upgradeImages();
    setTimeout(function() { scrollThroughPage(0); }, 300);
  });
  var ticks = 0;
  var timer = setInterval(function() {
    upgradeImages();
    ticks += 1;
    if (ticks > 40) clearInterval(timer);
  }, 500);
})();
</script>
''';

    final withHeadPatch = cleanedHtml.contains(RegExp('</head>', caseSensitive: false))
        ? cleanedHtml.replaceFirst(RegExp('</head>', caseSensitive: false), '$headPatch</head>')
        : '$headPatch$cleanedHtml';

    return withHeadPatch.contains(RegExp('</body>', caseSensitive: false))
        ? withHeadPatch.replaceFirst(RegExp('</body>', caseSensitive: false), '$bodyPatch</body>')
        : '$withHeadPatch$bodyPatch';
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

  static const String _wechatMobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
      'MicroMessenger/8.0.49';
}

class _PrintablePage {
  const _PrintablePage({
    required this.uri,
    required this.tempDir,
  });

  final String uri;
  final Directory tempDir;

  Future<void> cleanup() async {
    await tempDir.delete(recursive: true).catchError((_) => tempDir);
  }
}
