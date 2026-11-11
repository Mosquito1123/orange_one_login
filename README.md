# orange_one_login

Orange One Login：开源的一键登录 **Flutter SDK**。

它按运营商号码认证的公开步骤组织业务：初始化、判断蜂窝网络、预取号、授权页确认、取 `loginToken`、向**自己的**服务端换会话；网络不支持或用户改走其他方式时，发短信验证码。交互顺序参考 [极光 JVerify](https://pub.dev/packages/jverify) 的公开接口，但这里没有捆绑极光或运营商的闭源原生 SDK，也没有把 AppKey 发给第三方。

## 业务入口

```dart
import 'package:orange_one_login/orange_one_login.dart';

final client = OneClickClient(
  gateway: DemoCarrierGateway(
    operator: MobileOperator.cmcc,
    maskedNumber: '138****8000',
  ),
  // 生产环境换成 HttpSessionExchanger，把 loginToken 交给自己的账号服务。
  session: LocalSessionExchanger(),
);

await client.setup(appKey: 'your-app-key', channel: 'developer-default');

final env = await client.checkVerifyEnable();
if (!env.supported) {
  final sms = await client.getSmsCode('13800138000');
  // sms.challenge.uuid 交给自己的短信校验接口
  return;
}

final result = await client.signIn(context);
if (result.ok) {
  final sessionId = result.session!.sessionId;
}
```

`signIn` 会先 `prepare`（网络检查 + 预取号），再打开授权页。用户勾选协议并确认后拿到 loginToken，再交给 `SessionExchanger`。

| 方法 | 作用 |
| --- | --- |
| `setup` | 初始化。未调用时后续接口返回 `3001` |
| `checkVerifyEnable` | 当前网络能否做号码认证 |
| `preLogin` / `validPreLoginCache` / `clearPreLoginCache` | 预取掩码号并缓存 |
| `getToken` | 号码认证 token，演示实现 1 分钟过期，成功码 `2000` |
| `loginAuth` / `signIn` | 授权页。成功 `6000`，取消 `6002`，改走其他方式 `6004` |
| `getSmsCode` | 短信兜底。成功 `3000`，号码非法 `3002`，间隔过短 `3003` |
| `setAuthorizationTheme` | 导航、按钮文案、协议、自定义入口 |

授权页默认不勾选协议。未勾选就点登录会留在页面上，并提示「请先阅读并同意相关协议」。

## 换成真实网关

实现 `CarrierAuthGateway`，在 `authorize` 里向自己的号码认证通道要 loginToken。`HttpSessionExchanger` 会 `POST`：

```json
{
  "loginToken": "...",
  "operator": "CM",
  "maskedNumber": "138****8000"
}
```

成功响应至少包含 `sessionId`，可选 `expiresIn`（秒）或 `expiresAt`。

`DemoCarrierGateway` 只在进程内模拟中国移动 / 联通 / 电信的掩码号和 token，token 以 `ocl.` 开头。把 `cellular` 设为 `false` 即模拟 Wi-Fi，返回 `2016`。

## 三家运营商换号

客户端 SDK 只拿到一次性 token。下面三个类在**业务服务端**把 token 换成手机号，不要把 appSecret 或 RSA 私钥打进 App。出口 IP 需要在各家开放平台加白名单。

| 运营商 | 文档 | 服务端接口 |
| --- | --- | --- |
| 中国移动 | [号码认证](https://dev.10086.cn/numIdentific) | `POST https://www.cmpassport.com/unisdk/rsapi/loginTokenValidate`，`sign = MD5(appid + version + msgid + systemtime + strictcheck + token + appSecret)` 大写。成功码 `103000`。本机号码校验是 `POST https://www.cmpassport.com/openapi/rs/tokenValidate` |
| 中国联通 | [开店文档](https://kaidian.10010.com/docInside) | `POST https://opencloud.wostore.cn/openapi/netauth/tokenValidate`，`sign = MD5(appId + accessToken + timeStamp + appSecret)` 大写。控制台若给出别的路径，传给 `CuccAuthClient.endpoint` |
| 中国电信 | [天翼账号免密登录](https://id.dlife.cn/api?initialSrc=/html/api_detail_391.html) | `POST https://open.e.189.cn/auth/sdkcodeinfo.do`。`params` 是 `XXTea(accessCode=...&authCode=...)`，`sign` 是对 `appId + format + params + timeStamp` 做 SHA1withRSA |

```dart
final session = ThreeCarrierSessionExchanger(
  cmcc: CmccAuthClient(appId: cmccAppId, appSecret: cmccSecret),
  cucc: CuccAuthClient(appId: cuccAppId, appSecret: cuccSecret),
  ctcc: CtccAuthClient(
    appId: ctccAppId,
    appSecret: ctccSecret,
    rsaPrivateKeyPem: ctccPrivateKeyPem,
  ),
);
```

电信客户端 token 放 `accessCode`，`authCode` 放在 `CarrierToken.extras['authCode']`。

## 示例

```bash
cd example
flutter pub get
flutter run
```

## 测试

```bash
flutter test
```
