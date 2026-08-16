import 'package:flutter/material.dart';

/// 轻提示
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
    ));
}

/// 确认对话框（对应原 appConfirm）
Future<bool> appConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String okText = '确定',
  String cancelText = '取消',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 文本输入对话框
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result;
}
