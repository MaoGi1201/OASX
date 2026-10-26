import 'package:flutter/material.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/config_transfer_models.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/browser_download_io.dart'
    if (dart.library.html) 'package:oasx/utils/browser_download_web.dart';
import 'package:oasx/utils/file_save_stub.dart'
    if (dart.library.io) 'package:oasx/utils/file_save_io.dart';
import 'package:oasx/utils/app_toast.dart';

class ConfigActions {
  const ConfigActions._();

  static String? validateRenameName({
    required String oldName,
    required String newName,
    required ScriptService scriptService,
  }) {
    if (newName.isEmpty) {
      return I18n.nameCannotEmpty.tr;
    }
    if (['Home', 'home'].contains(newName)) {
      return I18n.nameInvalid.tr;
    }
    if (oldName == newName || scriptService.scriptOrderList.contains(newName)) {
      return I18n.nameDuplicate.tr;
    }
    return null;
  }

  static Future<bool> renameScript({
    required ScriptService scriptService,
    required String oldName,
    required String newName,
  }) async {
    final canRename = await scriptService.tryCloseScriptWithReason(oldName);
    if (!canRename) return false;

    final success = await scriptService.renameConfig(oldName, newName);
    if (!success) {
      showToast(I18n.error.tr, '');
    }
    return success;
  }

  static Future<String?> showRenameDialog({
    required ScriptService scriptService,
    required String oldName,
  }) async {
    final navigatorContext = Get.context ?? Get.key.currentContext;
    if (navigatorContext == null) {
      return null;
    }
    var newName = oldName;
    final formKey = GlobalKey<FormState>();

    Future<void> submit(BuildContext dialogContext) async {
      if (!(formKey.currentState?.validate() ?? false)) {
        return;
      }
      final renamed = await renameScript(
        scriptService: scriptService,
        oldName: oldName,
        newName: newName,
      );
      if (!renamed) {
        return;
      }
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop(newName);
      }
    }

    return showDialog<String>(
      context: navigatorContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(I18n.rename.tr),
          content: SizedBox(
            width: 320,
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: TextFormField(
                initialValue: oldName,
                autofocus: true,
                decoration: InputDecoration(labelText: I18n.newName.tr),
                validator: (String? value) {
                  final input = value?.trim() ?? '';
                  return validateRenameName(
                    oldName: oldName,
                    newName: input,
                    scriptService: scriptService,
                  );
                },
                onChanged: (v) => newName = v.trim(),
                onFieldSubmitted: (_) => submit(dialogContext),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(I18n.cancel.tr),
            ),
            FilledButton(
              onPressed: () => submit(dialogContext),
              child: Text(I18n.confirm.tr),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showDeleteDialog({
    required ScriptService scriptService,
    required String name,
  }) async {
    final navigatorContext = Get.context ?? Get.key.currentContext;
    if (navigatorContext == null) {
      return;
    }

    // 先弹确认框：确认之前不要碰脚本，否则取消后配置会被关掉（状态点变色）。
    final confirmed = await showDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(I18n.delete.tr),
          content: SizedBox(
            width: 320,
            child: Text(
              '${I18n.deleteConfirm.tr} "$name"?',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(I18n.cancel.tr),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(I18n.delete.tr),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final canDelete = await scriptService.tryCloseScriptWithReason(name);
    if (!canDelete) {
      return;
    }
    final success = await scriptService.deleteConfig(name);
    if (!success) {
      showToast(I18n.error.tr, '');
    }
  }

  static Future<void> exportScript({required String name}) async {
    try {
      final payload = await ApiClient().exportConfig(name);
      if (kIsWeb) {
        await downloadBytesToBrowser(
          payload.bytes,
          payload.fileName,
          mimeType: 'application/json',
        );
        showToast(I18n.tip.tr, I18n.configExportSuccess.tr);
        return;
      }
      final path = await FilePicker.platform.saveFile(
        fileName: payload.fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: payload.bytes,
      );
      if (path == null || path.trim().isEmpty) {
        return;
      }
      if (shouldWritePickedSavePath()) {
        await saveBytesToPath(path, payload.bytes);
      }
      showToast(I18n.tip.tr, I18n.configExportSuccess.tr);
    } catch (e) {
      final message = e is ConfigTransferException
          ? e.message
          : I18n.configExportFailed.tr;
      showToast(I18n.tip.tr, message);
    }
  }
}
