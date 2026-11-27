# 定时锁屏 LockTimer

到点自动锁屏 / 关机的 macOS 小工具。顶部切换「锁屏」或「关机」，输入分钟或小时（支持小数，如 1.5 小时），开始后倒计时：

- **锁屏**：到时间自动锁定屏幕（等同 ⌃⌘Q）
- **关机**：到时间以 root 执行 `shutdown -h now` 直接关机，不等待其他 App，**未保存的内容会丢失**

- 菜单栏显示剩余时间，可快速开始 / 延长 / 取消 / 立即锁屏
- 关闭窗口后继续在菜单栏计时；锁屏前 1 分钟提示音并弹出窗口（可关闭）
- 支持 macOS 13+，Apple 芯片与 Intel 通用

## 关机授权

第一次使用关机时会弹出系统管理员密码框，授权后写入 `/etc/sudoers.d/locktimer`，只允许无密码执行 `/sbin/shutdown -h now` 这一条命令。
撤销授权：`sudo rm /etc/sudoers.d/locktimer`

Mac 在倒计时中睡眠并错过关机时间时，唤醒后会先给 1 分钟缓冲再关机。

## 构建

```bash
./build.sh   # 产物：build/定时锁屏-<版本>.pkg
```

界面：[Lucian UX/UI Prompt](https://lucianlabs.dev/uxui-prompt/)（#067 / #047 / #018 / #039，MIT）。
类似项目：[ForceLock](https://github.com/guomengtao/ForceLock)。
