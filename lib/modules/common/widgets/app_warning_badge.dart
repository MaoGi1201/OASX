import 'package:flutter/material.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';

/// 挂在按钮右上角的异常角标。
///
/// 用 [AppColors.yellow]（后端「卡死」语义已经在用的色）配 [AppColors.onWarning]
/// 深色字，外面描一圈 [AppColors.bg] 让圆点从按钮描边里浮出来 —— 角标有一半
/// 落在按钮之外，不描边的话会和顶栏背景糊在一起。
///
/// 尺寸固定在 15px 高：再小数字挤不出可读的字号，再大就会压住相邻按钮。
class AppWarningBadge extends StatelessWidget {
  const AppWarningBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      constraints: const BoxConstraints(minWidth: 15),
      padding: const EdgeInsets.symmetric(horizontal: 3.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.yellow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.bg, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: count > 99 ? 8 : 9,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: AppColors.onWarning,
        ),
      ),
    );
  }
}
