# 定时锁屏 LockTimer

到点自动锁屏的 macOS 小工具。输入分钟或小时（支持小数，如 1.5 小时），开始后倒计时，到时间自动锁定屏幕（等同 ⌃⌘Q）。

- 菜单栏显示剩余时间，可快速开始 / 延长 / 取消 / 立即锁屏
- 关闭窗口后继续在菜单栏计时；锁屏前 1 分钟提示音并弹出窗口（可关闭）
- 支持 macOS 13+，Apple 芯片与 Intel 通用

## 构建

```bash
./build.sh   # 产物：build/定时锁屏-<版本>.pkg
```

界面：[Lucian UX/UI Prompt](https://lucianlabs.dev/uxui-prompt/)（#067 / #047 / #018，MIT）。
类似项目：[ForceLock](https://github.com/guomengtao/ForceLock)。
