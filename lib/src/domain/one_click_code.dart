/// 业务结果码。
///
/// 数值与运营商一键登录里公开的结果码对齐，方便从同类 SDK 迁过来时对照日志。
/// 本包自己的扩展码只有 [OneClickCode.switchedToOther]，表示用户在授权页改走其他登录。
enum OneClickCode {
  verifyConsistent(1000, '手机号验证一致'),
  verifyInconsistent(1001, '手机号验证不一致'),
  unknownResult(1002, '未知结果'),
  tokenExpired(1003, 'token 已失效'),
  verifyClosed(1004, '认证未开启'),
  appKeyMissing(1005, 'AppKey 不存在'),
  numberFrequencyLimit(1006, '同一号码今日认证次数超限'),
  appFrequencyLimit(1007, '应用今日认证次数超限'),
  appKeyIllegal(1008, 'AppKey 非法'),
  verifyIntervalTooShort(1010, '同一号码提交过于频繁'),
  appSignInvalid(1011, '应用签名错误'),

  tokenRequestSuccess(2000, '获取 token 成功'),
  fetchTokenError(2001, '获取 token 失败'),
  sdkInitFailed(2002, '初始化失败'),
  networkUnreachable(2003, '网络连接不通'),
  requestTimeout(2005, '请求超时'),
  fetchConfigFailed(2006, '获取配置失败'),
  internalError(2007, '内部异常'),
  tokenRequestInProgress(2008, '正在获取 token，请稍后再试'),
  verifyingInProgress(2009, '正在认证，请稍后再试'),
  networkNotSupported(2016, '当前网络环境不支持认证'),

  smsSent(3000, '短信验证码已发送'),
  notInitialized(3001, '尚未初始化'),
  invalidPhone(3002, '无效电话号码'),
  smsTooFrequent(3003, '两次请求间隔过短'),

  parameterInvalid(4001, '参数错误'),
  badServer(5000, '服务器未知错误'),

  loginTokenSuccess(6000, '获取 loginToken 成功'),
  loginTokenFailed(6001, '获取 loginToken 失败'),
  loginCancelled(6002, '用户取消登录'),
  switchedToOther(6004, '用户改用其他登录方式');

  const OneClickCode(this.value, this.defaultMessage);

  final int value;
  final String defaultMessage;

  bool get isSuccess =>
      this == tokenRequestSuccess ||
      this == loginTokenSuccess ||
      this == smsSent ||
      this == verifyConsistent;

  static OneClickCode? byValue(int value) {
    for (final code in OneClickCode.values) {
      if (code.value == value) return code;
    }
    return null;
  }
}
