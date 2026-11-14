/// 「全部配置」面板的筛选与排序规则。
///
/// 抽成纯函数是为了能单测：面板里的可见行为（关键词过滤、只显示异常、
/// 异常置顶）全在这里，widget 只负责把结果渲染出来。
library;

/// 过滤 [names] 并给异常配置排序。
///
/// - [query] 按大小写不敏感的子串匹配；
/// - [onlyWarning] 为 true 时只保留 [warnings] 里的配置；
/// - 未开 [onlyWarning] 时把 [warnings] 里的配置提到最前，**其余保持原顺序**。
///   不做名称二级排序：列表顺序要和顶栏标签、后端 `scriptOrderList` 对得上，
///   自己排一遍会让用户找不到刚才看到的配置。
List<String> filterAllConfigs(
  List<String> names, {
  String query = '',
  bool onlyWarning = false,
  Set<String> warnings = const <String>{},
}) {
  final keyword = query.trim().toLowerCase();
  bool matchesQuery(String name) =>
      keyword.isEmpty || name.toLowerCase().contains(keyword);

  if (onlyWarning) {
    return names
        .where(warnings.contains)
        .where(matchesQuery)
        .toList(growable: false);
  }

  final visible = names.where(matchesQuery).toList(growable: false);
  if (warnings.isEmpty) {
    return visible;
  }
  return <String>[
    ...visible.where(warnings.contains),
    ...visible.where((name) => !warnings.contains(name)),
  ];
}
