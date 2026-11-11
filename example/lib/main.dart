import 'package:flutter/material.dart';
import 'package:orange_one_login/orange_one_login.dart';

void main() {
  runApp(const OneClickDemoApp());
}

class OneClickDemoApp extends StatelessWidget {
  const OneClickDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '一键登录',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F6E6B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F1E8),
      ),
      home: const DemoHome(),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final _gateway = DemoCarrierGateway();
  late final OneClickClient _client = OneClickClient(gateway: _gateway, debug: true);
  final _log = <String>[];
  var _ready = false;
  var _cellular = true;

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    await _client.setup(appKey: 'demo-app-key', channel: 'developer-default');
    _client.setAuthorizationTheme(
      AuthPageTheme(
        clauses: [
          PrivacyClause(name: '服务协议', url: Uri.parse('https://example.com/terms')),
          PrivacyClause(name: '隐私政策', url: Uri.parse('https://example.com/privacy')),
        ],
        actions: const [AuthAction(id: 'help', title: '遇到问题')],
      ),
    );
    setState(() => _ready = true);
    _write('已初始化');
  }

  Future<void> _signIn() async {
    if (!_ready) await _setup();
    if (!mounted) return;
    final result = await _client.signIn(context);
    _write('[${result.code.value}] ${result.message}'
        '${result.session == null ? '' : ' session=${result.session!.sessionId}'}');
    if (result.code == OneClickCode.switchedToOther && mounted) {
      final sms = await _client.getSmsCode('13800138000');
      _write('短信 [${sms.code.value}] ${sms.message}');
    }
  }

  Future<void> _token() async {
    if (!_ready) await _setup();
    final env = await _client.checkVerifyEnable();
    if (!env.supported) {
      _write('[2016] ${env.message}');
      return;
    }
    final token = await _client.getToken();
    _write('[${token.code.value}] ${token.message}');
  }

  void _write(String line) {
    setState(() => _log.insert(0, line));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('一键登录示例')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('模拟蜂窝网络'),
            subtitle: Text(_gateway.operator.slogan),
            value: _cellular,
            onChanged: (value) {
              setState(() {
                _cellular = value;
                _gateway.cellular = value;
              });
            },
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _signIn, child: const Text('本机号码一键登录')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _token, child: const Text('仅获取认证 token')),
          const SizedBox(height: 20),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}
