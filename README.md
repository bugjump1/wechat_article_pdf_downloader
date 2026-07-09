# 微信公众号 PDF 下载器（Flutter / Material Design 3）

这是一个 Flutter 源码包，用来把公开微信公众号推文链接导出为 PDF：

- 首页中央 Material Design 3 卡片式输入框
- 微信公众号链接格式校验
- 点击「下载」后显示进度条和状态文案
- Android / iOS：隐藏原生 WebView 加载文章，滚动触发懒加载图片，生成 PDF 后调用系统分享
- Windows：调用系统保存位置选择框，然后使用 Edge / Chrome headless 打印为 PDF
- 默认包名前缀：`com.bugjump`，Android applicationId：`com.bugjump.wechatpdf`

## 重要说明

微信公众号页面存在动态加载、反爬、防盗链、临时链接过期等情况。本项目采用“真实浏览器/WebView 渲染后打印”的方案，已经尽量保留网页视觉格式，但无法保证所有历史文章、被限制访问文章、验证码文章、已删除文章都能成功导出。

## 推荐环境

- Flutter 3.38.1 或更新
- Dart 3.10 或更新
- Android：Java 17、Kotlin 2.2、Android Gradle Plugin 8.12+
- iOS：iOS 13+
- Windows：Windows 10/11，已安装 Microsoft Edge 或 Google Chrome

## 如何创建完整工程

当前压缩包包含完整业务源码和平台桥接代码。为了得到 Flutter 自动生成的 Runner、Gradle Wrapper、Xcode 工程和 Windows CMake 工程，按下面方式创建：

```bash
flutter create wechat_article_pdf_downloader --platforms=android,ios,windows --org com.bugjump
```

然后把本源码包里的文件复制到新创建的 `wechat_article_pdf_downloader` 目录，覆盖同名文件。

接着执行：

```bash
cd wechat_article_pdf_downloader
flutter pub get
```

## 运行

Android：

```bash
flutter run -d android
```

iOS：

```bash
cd ios
pod install
cd ..
flutter run -d ios
```

Windows：

```bash
flutter run -d windows
```

## 打包

Android APK：

```bash
flutter build apk --release
```

Android App Bundle：

```bash
flutter build appbundle --release
```

iOS：

```bash
flutter build ios --release
```

Windows：

```bash
flutter build windows --release
```

## 支持的链接格式

校验器会尽量支持常见公众号文章格式，包括：

- `https://mp.weixin.qq.com/s/xxxxx`
- `https://mp.weixin.qq.com/s?__biz=...&mid=...&idx=...&sn=...`
- `https://mp.weixin.qq.com/mp/appmsg/show?__biz=...&appmsgid=...&itemidx=...`

## 关键文件

- `lib/main.dart`：Material Design 3 UI、输入校验、进度条
- `lib/services/url_validator.dart`：微信公众号链接校验和标准化
- `lib/services/pdf_export_service.dart`：按平台分发导出逻辑
- `lib/services/native_pdf_bridge.dart`：Android/iOS 原生通道
- `lib/services/windows_edge_pdf_service.dart`：Windows Edge headless PDF 输出
- `android/app/src/main/kotlin/com/bugjump/wechatpdf/MainActivity.kt`：Android WebView 打印 PDF
- `ios/Runner/AppDelegate.swift`：iOS WKWebView + UIPrintPageRenderer 输出 PDF

## 为什么不是纯 Dart？

Flutter 可以一套 UI 多端复用，但“把网页完整渲染成 PDF”依赖系统浏览器内核和平台能力：Android 使用 WebView 的打印接口，iOS 使用 WKWebView 的打印格式器，Windows 使用 Edge/Chromium 的打印 PDF 能力。这样比直接抓 HTML 后用 Dart 重新排版更接近原网页。
