package com.bugjump.wechatpdf

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.pdf.PdfDocument
import android.os.Bundle
import android.view.View
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var activeWebView: WebView? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "renderArticleToPdf" -> {
                    val url = call.argument<String>("url")
                    val outputPath = call.argument<String>("outputPath")
                    val waitMillis = call.argument<Int>("waitForLazyImagesMillis") ?: 8000
                    if (url.isNullOrBlank() || outputPath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "url 或 outputPath 为空", null)
                        return@setMethodCallHandler
                    }
                    renderArticleToPdf(url, outputPath, waitMillis, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun renderArticleToPdf(
        url: String,
        outputPath: String,
        waitMillis: Int,
        result: MethodChannel.Result
    ) {
        runOnUiThread {
            activeWebView?.destroy()
            val completed = AtomicBoolean(false)
            val webView = WebView(this)
            activeWebView = webView

            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                loadsImagesAutomatically = true
                blockNetworkImage = false
                cacheMode = WebSettings.LOAD_DEFAULT
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                userAgentString = WECHAT_MOBILE_UA
                useWideViewPort = true
                loadWithOverviewMode = true
            }

            webView.webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView?, loadingUrl: String?, favicon: android.graphics.Bitmap?) {
                    sendProgress(12, "正在加载网页")
                }

                override fun onPageFinished(view: WebView?, finishedUrl: String?) {
                    val loadedView = view ?: return
                    sendProgress(42, "网页加载完成，等待图片资源")
                    val initialDelay = waitMillis.coerceAtLeast(3000).toLong() / 3L
                    loadedView.postDelayed({
                        scrollAndPatchImages(loadedView, 0, waitMillis, outputPath, completed, result)
                    }, initialDelay)
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: WebResourceError?
                ) {
                    val failedView = view ?: return
                    if (request?.isForMainFrame == true && completed.compareAndSet(false, true)) {
                        cleanup(failedView)
                        result.error(
                            "WEB_LOAD_ERROR",
                            "网页加载失败：${error?.description ?: "未知错误"}",
                            null
                        )
                    }
                }
            }

            sendProgress(8, "正在创建 WebView")
            webView.loadUrl(url)
        }
    }

    private fun scrollAndPatchImages(
        webView: WebView,
        step: Int,
        waitMillis: Int,
        outputPath: String,
        completed: AtomicBoolean,
        result: MethodChannel.Result
    ) {
        if (completed.get()) return

        if (step < SCROLL_STEPS) {
            val progress = 45 + (step * 4)
            sendProgress(progress, "正在滚动页面以触发懒加载图片")
            val ratio = (step + 1).toDouble() / SCROLL_STEPS.toDouble()
            val js = """
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
                  window.scrollTo(0, Math.floor(h * $ratio));
                  return h;
                })();
            """.trimIndent()
            webView.evaluateJavascript(js, null)
            webView.postDelayed({
                scrollAndPatchImages(webView, step + 1, waitMillis, outputPath, completed, result)
            }, waitMillis.coerceAtLeast(3000).toLong() / SCROLL_STEPS.toLong())
            return
        }

        sendProgress(78, "正在整理打印样式")
        val printCssJs = """
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
        """.trimIndent()
        webView.evaluateJavascript(printCssJs) {
            webView.postDelayed({
                writeWebViewToPdf(webView, outputPath, completed, result)
            }, 1200)
        }
    }

    private fun writeWebViewToPdf(
        webView: WebView,
        outputPath: String,
        completed: AtomicBoolean,
        result: MethodChannel.Result
    ) {
        if (completed.get()) return
        sendProgress(84, "正在渲染 PDF")
        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) outputFile.delete()

        var pdfDocument: PdfDocument? = null
        try {
            val pageWidth = 595
            val pageHeight = 842
            val contentWidth = (webView.width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels)
                .coerceAtLeast(1)
            val initialContentHeight = (webView.contentHeight * webView.scale).toInt()
                .coerceAtLeast(webView.height)
                .coerceAtLeast(1)

            webView.measure(
                View.MeasureSpec.makeMeasureSpec(contentWidth, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(initialContentHeight, View.MeasureSpec.EXACTLY)
            )
            val contentHeight = webView.measuredHeight.coerceAtLeast(initialContentHeight)
            webView.layout(0, 0, contentWidth, contentHeight)

            val scale = pageWidth.toFloat() / contentWidth.toFloat()
            val pageContentHeight = (pageHeight / scale).toInt().coerceAtLeast(1)
            val pageCount = ((contentHeight + pageContentHeight - 1) / pageContentHeight).coerceAtLeast(1)

            val document = PdfDocument()
            pdfDocument = document
            for (pageIndex in 0 until pageCount) {
                val pageInfo = PdfDocument.PageInfo.Builder(pageWidth, pageHeight, pageIndex + 1).create()
                val page = document.startPage(pageInfo)
                page.canvas.drawColor(Color.WHITE)
                page.canvas.scale(scale, scale)
                page.canvas.translate(0f, -(pageIndex * pageContentHeight).toFloat())
                webView.draw(page.canvas)
                document.finishPage(page)
            }

            sendProgress(90, "正在写入 PDF 文件")
            outputFile.outputStream().use { stream ->
                document.writeTo(stream)
            }
            if (completed.compareAndSet(false, true)) {
                sendProgress(100, "PDF 生成完成")
                cleanup(webView)
                result.success(outputPath)
            }
        } catch (error: Throwable) {
            if (completed.compareAndSet(false, true)) {
                cleanup(webView)
                result.error("PDF_RENDER_ERROR", error.message ?: error.toString(), null)
            }
        } finally {
            pdfDocument?.close()
        }
    }

    private fun cleanup(webView: WebView) {
        runOnUiThread {
            if (activeWebView === webView) activeWebView = null
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.destroy()
        }
    }

    private fun sendProgress(value: Int, message: String) {
        runOnUiThread {
            channel?.invokeMethod(
                "progress",
                mapOf("value" to value.coerceIn(0, 100), "message" to message)
            )
        }
    }

    companion object {
        private const val CHANNEL = "com.bugjump.wechat_article_pdf/native_pdf"
        private const val SCROLL_STEPS = 8
        private const val WECHAT_MOBILE_UA =
            "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Version/4.0 Chrome/124.0 Mobile Safari/537.36 " +
                "MicroMessenger/8.0.49"
    }
}
