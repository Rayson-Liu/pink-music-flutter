import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 极验(geetest)人机验证结果
class GeetestResult {
  final String validate;
  final String seccode;
  const GeetestResult({required this.validate, required this.seccode});
}

/// 弹出极验人机验证（滑动拼图），完成返回 validate/seccode，失败或取消返回 null。
Future<GeetestResult?> showGeetestCaptcha(
  BuildContext context, {
  required String gt,
  required String challenge,
}) {
  return showDialog<GeetestResult>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _GeetestDialog(gt: gt, challenge: challenge),
  );
}

class _GeetestDialog extends StatefulWidget {
  final String gt;
  final String challenge;
  const _GeetestDialog({required this.gt, required this.challenge});

  @override
  State<_GeetestDialog> createState() => _GeetestDialogState();
}

class _GeetestDialogState extends State<_GeetestDialog> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel('GeeTest', onMessageReceived: (msg) {
        _onMessage(msg.message);
      })
      ..loadHtmlString(_buildHtml(widget.gt, widget.challenge));
  }

  void _onMessage(String raw) {
    if (!mounted || _done) return;
    if (raw == 'READY') {
      setState(() => _loading = false);
      return;
    }
    if (raw.startsWith('ERROR')) {
      _done = true;
      debugPrint('极验验证失败: $raw');
      Navigator.pop(context);
      return;
    }
    try {
      final map = jsonDecode(raw);
      final validate = map['validate']?.toString() ?? '';
      final seccode = map['seccode']?.toString() ?? '';
      if (validate.isNotEmpty && seccode.isNotEmpty) {
        _done = true;
        Navigator.pop(
            context, GeetestResult(validate: validate, seccode: seccode));
      }
    } catch (_) {}
  }

  String _buildHtml(String gt, String challenge) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<script src="https://static.geetest.com/static/tools/gt.js"></script>
<style>body{margin:0;padding:16px;background:#ffffff;}</style>
</head>
<body>
<div id="captcha"></div>
<script>
var __tried = 0;
function fail(msg) { GeeTest.postMessage('ERROR:' + msg); }
function start() {
  if (typeof initGeetest === 'undefined') {
    if (__tried++ > 30) { fail('gt.js not loaded'); return; }
    setTimeout(start, 300);
    return;
  }
  try {
    initGeetest({
      gt: '$gt',
      challenge: '$challenge',
      offline: false,
      new_captcha: true,
      product: 'bind',
      width: '300px'
    }, function(captchaObj) {
      captchaObj.appendTo('#captcha');
      captchaObj.onReady(function() { GeeTest.postMessage('READY'); });
      captchaObj.onSuccess(function() {
        var r = captchaObj.getValidate();
        GeeTest.postMessage(JSON.stringify({validate: r.geetest_validate, seccode: r.geetest_seccode}));
      });
      captchaObj.onError(function(err) { fail('geetest error: ' + JSON.stringify(err)); });
    });
  } catch (e) { fail(e.message || 'init error'); }
}
start();
</script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 300,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const ColoredBox(
                color: Colors.white,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
