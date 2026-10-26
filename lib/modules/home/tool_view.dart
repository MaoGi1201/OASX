import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Content of the "推送测试" dialog: three fields plus a send button.
///
/// Kept as plain content (no Card, no duplicated title) because the dialog
/// itself provides the frame.
class NotifyTest extends StatefulWidget {
  const NotifyTest({Key? key}) : super(key: key);

  @override
  NotifyTestState createState() => NotifyTestState();
}

class NotifyTestState extends State<NotifyTest> {
  late final TextEditingController _configController =
      TextEditingController(text: 'provider:');
  late final TextEditingController _titleController =
      TextEditingController(text: 'Title');
  late final TextEditingController _contentController =
      TextEditingController(text: 'Content');

  @override
  void dispose() {
    _configController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _send() {
    ApiClient().notifyTest(
      _configController.text,
      _titleController.text,
      _contentController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            controller: _configController,
            label: I18n.notifyTestConfig.tr,
            helper: I18n.notifyTestHelp.tr,
            minLines: 3,
            maxLines: 6,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _titleController,
            label: I18n.notifyTestTitle.tr,
            minLines: 1,
            maxLines: 1,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _contentController,
            label: I18n.notifyTestContent.tr,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: _send,
              child: Text(I18n.notifyTestSend.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    required int minLines,
    required int maxLines,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
