import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app.dart';
import '../state/user_store.dart';
import 'widgets/geetest_captcha.dart';

/// 登录面板：扫码登录 + 手机验证码登录（双模式）
class LoginPanel extends StatefulWidget {
  const LoginPanel({super.key});

  @override
  State<LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<LoginPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录哔哩哔哩'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '扫码登录'),
            Tab(text: '短信登录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_QrLoginTab(), _SmsLoginTab()],
      ),
    );
  }
}

// ---------------- 扫码登录 ----------------

class _QrLoginTab extends StatefulWidget {
  const _QrLoginTab();

  @override
  State<_QrLoginTab> createState() => _QrLoginTabState();
}

class _QrLoginTabState extends State<_QrLoginTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppServices.instance.user.generateQrcode();
    });
  }

  @override
  void dispose() {
    AppServices.instance.user.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: svc.user,
      builder: (context, _) {
        final user = svc.user;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 240,
                  height: 240,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildQr(user, theme),
                ),
                const SizedBox(height: 20),
                Text(user.qrcodeMessage,
                    style: TextStyle(
                        color: user.qrcodeStatus == 'error' ||
                                user.qrcodeStatus == 'expired'
                            ? theme.colorScheme.error
                            : theme.hintColor)),
                const SizedBox(height: 8),
                if (user.qrcodeStatus == 'loading')
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                if (user.qrcodeStatus == 'error' ||
                    user.qrcodeStatus == 'expired' ||
                    user.qrcodeStatus == 'idle')
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新二维码'),
                    onPressed: () => svc.user.generateQrcode(),
                  ),
                if (user.isLoggedIn) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('登录成功'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
                const SizedBox(height: 24),
                Text('打开哔哩哔哩 App，扫描二维码即可登录',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQr(UserStore user, ThemeData theme) {
    if (user.qrcodeStatus == 'loading') {
      return const Center(child: CircularProgressIndicator());
    }
    if (user.qrcodeUrl.isEmpty) {
      return Center(
        child: Icon(Icons.qr_code, size: 80, color: theme.hintColor),
      );
    }
    return QrImageView(
      data: user.qrcodeUrl,
      size: 216,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
  }
}

// ---------------- 短信验证码登录 ----------------

class _SmsLoginTab extends StatefulWidget {
  const _SmsLoginTab();

  @override
  State<_SmsLoginTab> createState() => _SmsLoginTabState();
}

class _SmsLoginTabState extends State<_SmsLoginTab> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _sendSms() async {
    final svc = AppServices.instance;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    if (!RegExp(r'^\d{6,15}$').hasMatch(phone)) {
      _toast('手机号格式错误');
      return;
    }
    setState(() => _busy = true);
    try {
      final captcha = await svc.user.fetchSmsCaptcha();
      if (captcha == null) {
        _toast(svc.user.smsMessage.isNotEmpty
            ? svc.user.smsMessage
            : '获取验证码失败');
        return;
      }
      final gt = captcha['gt']?.toString() ?? '';
      final challenge = captcha['challenge']?.toString() ?? '';
      if (gt.isEmpty || challenge.isEmpty) {
        _toast('获取人机验证失败');
        return;
      }
      if (!mounted) return;
      final result =
          await showGeetestCaptcha(context, gt: gt, challenge: challenge);
      if (result == null) {
        _toast('人机验证未完成');
        return;
      }
      final ok = await svc.user
          .sendSmsCode(phone, captcha, result.validate, result.seccode);
      _toast(ok ? '验证码已发送' : svc.user.smsMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    final svc = AppServices.instance;
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _toast('请输入手机号和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await svc.user.loginWithSms(phone, code);
      if (ok) {
        if (mounted) Navigator.pop(context);
      } else {
        _toast(svc.user.smsMessage.isNotEmpty ? svc.user.smsMessage : '登录失败');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: svc.user,
      builder: (context, _) {
        final user = svc.user;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.smartphone,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('手机号验证码登录',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  prefixText: '+86 ',
                  hintText: '请输入手机号',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: '验证码', hintText: '请输入短信验证码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _sendSms,
                      child: Text(_busy ? '处理中…' : '获取验证码'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: Text(_busy ? '登录中…' : '登录'),
              ),
              if (user.smsMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  user.smsMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: user.smsStatus == 'error'
                          ? theme.colorScheme.error
                          : theme.hintColor),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
