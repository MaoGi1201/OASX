part of 'log_widget.dart';

class LogContent extends StatelessWidget {
  const LogContent({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.onUserScroll,
  });

  final LogMixin controller;
  final ScrollController scrollController;
  final Function() onUserScroll;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          onUserScroll();
          return false;
        },
        child: Obx(
          () => ListView.builder(
            controller: scrollController,
            itemCount: controller.logs.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: EasyRichText(
                controller.logs[index],
                patternList: _buildPatterns(),
                selectable: true,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                defaultStyle: _selectStyle(context),
              ),
            ),
          ).paddingAll(10),
        ),
      ),
    ).constrained(width: double.infinity, height: double.infinity);
  }

  /// 等宽数字，避免时间戳在滚动时抖动。
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// 日志高亮样式：颜色来自主题令牌，随明暗切换，所以不能是 const。
  static TextStyle _logStyle(Color color) =>
      TextStyle(color: color, fontFeatures: _tabular);

  List<EasyRichTextPattern> _buildPatterns() {
    return [
      EasyRichTextPattern(
        targetString: 'INFO',
        style: _logStyle(AppColors.logInfo),
        suffixInlineSpan: const TextSpan(
          style: TextStyle(fontFeatures: _tabular),
          text: '      ',
        ),
      ),
      EasyRichTextPattern(
        targetString: 'WARNING',
        style: _logStyle(AppColors.logWarn),
      ),
      EasyRichTextPattern(
        targetString: 'ERROR',
        style: _logStyle(AppColors.logError),
        suffixInlineSpan: const TextSpan(
          style: TextStyle(fontFeatures: _tabular),
          text: '    ',
        ),
      ),
      EasyRichTextPattern(
        targetString: 'CRITICAL',
        style: _logStyle(AppColors.logError),
        suffixInlineSpan: const TextSpan(text: '   '),
      ),
      EasyRichTextPattern(
        targetString: r'(\d{2}:\d{2}:\d{2}\.\d{3})',
        style: _logStyle(AppColors.logInfo),
      ),
      const EasyRichTextPattern(
        targetString: r'[\{\[\(\)\]\}]',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      EasyRichTextPattern(
        targetString: 'True',
        style: _logStyle(AppColors.logSuccess),
      ),
      EasyRichTextPattern(
        targetString: 'False',
        style: _logStyle(AppColors.logError),
      ),
      EasyRichTextPattern(
        targetString: 'None',
        style: _logStyle(AppColors.logDebug),
      ),
      EasyRichTextPattern(
        targetString: r'(某喵*某喵)|(~~*~~)',
        style: _logStyle(AppColors.logSuccess),
      ),
    ];
  }

  TextStyle _selectStyle(BuildContext context) {
    return context.mediaQuery.orientation == Orientation.portrait
        ? Theme.of(context).textTheme.bodySmall!
        : Theme.of(context).textTheme.titleSmall!;
  }
}
