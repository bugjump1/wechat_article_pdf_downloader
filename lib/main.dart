import 'dart:io';

import 'package:flutter/material.dart';

import 'services/pdf_export_service.dart';
import 'services/url_validator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WeChatPdfApp());
}

class WeChatPdfApp extends StatelessWidget {
  const WeChatPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '微信公众号 PDF',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF81C784),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _linkController = TextEditingController();
  final FocusNode _linkFocusNode = FocusNode();

  bool _busy = false;
  double _progress = 0;
  String _statusText = '等待输入微信公众号推文链接';
  String? _errorText;

  @override
  void dispose() {
    _linkController.dispose();
    _linkFocusNode.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final rawUrl = _linkController.text.trim();
    final normalizedUrl = WeChatArticleUrlValidator.normalize(rawUrl);

    setState(() {
      _errorText = null;
    });

    if (normalizedUrl == null) {
      setState(() {
        _errorText = '请输入有效的微信公众号推文链接，例如 https://mp.weixin.qq.com/s/...';
      });
      _linkFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _progress = 0.02;
      _statusText = '准备加载网页';
    });

    try {
      final result = await PdfExportService.exportWeChatArticle(
        url: normalizedUrl.toString(),
        onProgress: (value, message) {
          if (!mounted) return;
          setState(() {
            _progress = value.clamp(0.0, 1.0);
            _statusText = message;
          });
        },
      );

      if (!mounted) return;
      switch (result.action) {
        case PdfExportAction.shared:
          messenger.showSnackBar(
            SnackBar(
              content: Text('PDF 已生成，系统分享面板已打开：${result.fileName}'),
            ),
          );
        case PdfExportAction.saved:
          messenger.showSnackBar(
            SnackBar(content: Text('PDF 已保存：${result.path}')),
          );
        case PdfExportAction.cancelled:
          messenger.showSnackBar(
            const SnackBar(content: Text('已取消保存')),
          );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('生成失败：$error'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = 0;
        _statusText = '等待输入微信公众号推文链接';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final platformText = Platform.isWindows
        ? 'Windows：生成后会弹出保存位置选择框'
        : Platform.isAndroid || Platform.isIOS
            ? 'Android / iOS：生成后会自动调用系统分享'
            : '当前平台暂未适配';

    return Scaffold(
      appBar: AppBar(
        title: const Text('微信公众号 PDF 下载器'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 52,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '把微信公众号推文保存为 PDF',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '尽量按原网页视觉排版导出正文、图片和样式。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _linkController,
                        focusNode: _linkFocusNode,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _download(),
                        decoration: InputDecoration(
                          labelText: '微信公众号推文链接',
                          hintText: 'https://mp.weixin.qq.com/s/...',
                          helperText: '支持 /s/...、/s?__biz=...、/mp/appmsg/show?... 等常见格式',
                          errorText: _errorText,
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _download,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(_busy ? '正在生成 PDF' : '下载'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: _busy
                            ? Padding(
                                key: const ValueKey('progress'),
                                padding: const EdgeInsets.only(top: 22),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    LinearProgressIndicator(
                                      value: _progress <= 0 ? null : _progress,
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _statusText,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : Padding(
                                key: const ValueKey('idle'),
                                padding: const EdgeInsets.only(top: 22),
                                child: Text(
                                  platformText,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
