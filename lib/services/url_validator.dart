class WeChatArticleUrlValidator {
  WeChatArticleUrlValidator._();

  static Uri? normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final withScheme = trimmed.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? trimmed
        : 'https://$trimmed';

    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    final host = uri.host.toLowerCase();
    if (host != 'mp.weixin.qq.com') return null;

    final path = uri.path.toLowerCase();
    final query = uri.queryParameters;

    final isShortArticle = path.startsWith('/s/') && path.length > 3;
    final isOldArticle = path == '/s' &&
        query.containsKey('__biz') &&
        (query.containsKey('mid') || query.containsKey('appmsgid')) &&
        (query.containsKey('idx') || query.containsKey('itemidx'));
    final isAppMsgArticle = path == '/mp/appmsg/show' &&
        query.containsKey('__biz') &&
        (query.containsKey('appmsgid') || query.containsKey('mid'));

    if (!isShortArticle && !isOldArticle && !isAppMsgArticle) return null;

    return uri.replace(scheme: 'https');
  }
}
