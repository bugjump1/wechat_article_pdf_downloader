import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var channel: FlutterMethodChannel?
  private var renderer: ArticlePdfRenderer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.bugjump.wechat_article_pdf/native_pdf",
      binaryMessenger: controller.binaryMessenger
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "renderArticleToPdf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let url = args["url"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "url 或 outputPath 为空", details: nil))
        return
      }
      let waitMillis = args["waitForLazyImagesMillis"] as? Int ?? 8000
      self?.renderer = ArticlePdfRenderer(
        urlString: url,
        outputPath: outputPath,
        waitMillis: waitMillis,
        hostView: controller.view,
        channel: channel,
        flutterResult: result,
        onFinish: { [weak self] in self?.renderer = nil }
      )
      self?.renderer?.start()
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class ArticlePdfRenderer: NSObject, WKNavigationDelegate {
  private let urlString: String
  private let outputPath: String
  private let waitMillis: Int
  private weak var hostView: UIView?
  private let channel: FlutterMethodChannel
  private var flutterResult: FlutterResult?
  private let onFinish: () -> Void
  private var webView: WKWebView?
  private var completed = false

  init(
    urlString: String,
    outputPath: String,
    waitMillis: Int,
    hostView: UIView,
    channel: FlutterMethodChannel,
    flutterResult: @escaping FlutterResult,
    onFinish: @escaping () -> Void
  ) {
    self.urlString = urlString
    self.outputPath = outputPath
    self.waitMillis = max(waitMillis, 3000)
    self.hostView = hostView
    self.channel = channel
    self.flutterResult = flutterResult
    self.onFinish = onFinish
    super.init()
  }

  func start() {
    guard let url = URL(string: urlString) else {
      fail(code: "BAD_URL", message: "链接格式无效")
      return
    }

    progress(8, "正在创建 WKWebView")
    let configuration = WKWebViewConfiguration()
    if #available(iOS 14.0, *) {
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    } else {
      configuration.preferences.javaScriptEnabled = true
    }

    let view = WKWebView(frame: CGRect(x: -10000, y: 0, width: 390, height: 844), configuration: configuration)
    view.navigationDelegate = self
    view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.49"
    view.scrollView.isScrollEnabled = true
    view.isOpaque = false
    view.alpha = 0.01

    hostView?.addSubview(view)
    webView = view
    progress(12, "正在加载网页")
    view.load(URLRequest(url: url))
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    progress(42, "网页加载完成，等待图片资源")
    let delay = Double(waitMillis) / 3000.0
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.scrollAndPatchImages(step: 0)
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    fail(code: "WEB_LOAD_ERROR", message: "网页加载失败：\(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    fail(code: "WEB_LOAD_ERROR", message: "网页加载失败：\(error.localizedDescription)")
  }

  private func scrollAndPatchImages(step: Int) {
    guard !completed, let webView else { return }

    if step < 8 {
      let value = 45 + step * 4
      progress(value, "正在滚动页面以触发懒加载图片")
      let ratio = Double(step + 1) / 8.0
      let js = """
      (function() {
        document.querySelectorAll('img').forEach(function(img) {
          var src = img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-backsrc');
          if (src && (!img.getAttribute('src') || img.getAttribute('src').indexOf('data:') === 0)) {
            img.setAttribute('src', src.replace(/^http:/, 'https:'));
          }
          img.style.maxWidth = '100%';
          img.style.height = 'auto';
        });
        var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
        window.scrollTo(0, Math.floor(h * \(ratio)));
        return h;
      })();
      """
      webView.evaluateJavaScript(js) { [weak self] _, _ in
        guard let self else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.waitMillis) / 8000.0) {
          self.scrollAndPatchImages(step: step + 1)
        }
      }
      return
    }

    progress(78, "正在整理打印样式")
    let finalJs = """
    (function() {
      document.querySelectorAll('img').forEach(function(img) {
        var src = img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('data-backsrc');
        if (src && (!img.getAttribute('src') || img.getAttribute('src').indexOf('data:') === 0)) {
          img.setAttribute('src', src.replace(/^http:/, 'https:'));
        }
        img.style.maxWidth = '100%';
        img.style.height = 'auto';
      });
      var style = document.getElementById('bugjump_pdf_print_style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'bugjump_pdf_print_style';
        style.innerHTML = '@media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } img { max-width: 100% !important; height: auto !important; } }';
        document.head.appendChild(style);
      }
      window.scrollTo(0, 0);
      return document.title || 'wechat_article';
    })();
    """
    webView.evaluateJavaScript(finalJs) { [weak self] _, _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self?.writePdf()
      }
    }
  }

  private func writePdf() {
    guard !completed, let webView else { return }
    progress(84, "正在渲染 PDF")

    let renderer = UIPrintPageRenderer()
    renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)

    let a4Width: CGFloat = 595.2
    let a4Height: CGFloat = 841.8
    let paperRect = CGRect(x: 0, y: 0, width: a4Width, height: a4Height)
    let printableRect = paperRect.insetBy(dx: 0, dy: 0)
    renderer.setValue(paperRect, forKey: "paperRect")
    renderer.setValue(printableRect, forKey: "printableRect")
    renderer.prepare(forDrawingPages: NSRange(location: 0, length: 0))

    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, paperRect, nil)
    let pageCount = renderer.numberOfPages
    if pageCount <= 0 {
      UIGraphicsEndPDFContext()
      fail(code: "PDF_EMPTY", message: "没有可导出的页面")
      return
    }

    for index in 0..<pageCount {
      UIGraphicsBeginPDFPage()
      progress(88 + min(index, 7), "正在写入第 \(index + 1) 页")
      renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
    }
    UIGraphicsEndPDFContext()

    do {
      let url = URL(fileURLWithPath: outputPath)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: .atomic)
      complete(path: outputPath)
    } catch {
      fail(code: "PDF_WRITE_FAILED", message: "PDF 写入失败：\(error.localizedDescription)")
    }
  }

  private func progress(_ value: Int, _ message: String) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("progress", arguments: [
        "value": max(0, min(value, 100)),
        "message": message
      ])
    }
  }

  private func complete(path: String) {
    guard !completed else { return }
    completed = true
    progress(100, "PDF 生成完成")
    flutterResult?(path)
    cleanup()
  }

  private func fail(code: String, message: String) {
    guard !completed else { return }
    completed = true
    flutterResult?(FlutterError(code: code, message: message, details: nil))
    cleanup()
  }

  private func cleanup() {
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView?.navigationDelegate = nil
    webView = nil
    flutterResult = nil
    onFinish()
  }
}
