# 牛马时光 WorkHorse

牛马时光是一款 macOS 菜单栏常驻工作记录应用。它用于记录当前任务、统计今日工作时长、提供专注提醒，并在下班后生成今日工作报告。

## 已实现

- macOS 菜单栏常驻入口
- 首次启动设置面板
- 工作日、工作时间、专注提醒、下班提醒、开机启动配置
- 工作开始任务输入气泡
- 当前任务计时
- 专注提醒：完成或继续当前任务
- 下班提醒：去打卡或继续工作并延后提醒
- 今日工作报告窗口
- 时间分布圆环图
- 复制 Markdown 日报
- 导出 CSV
- 本地 JSON 存储

## 运行

调试运行：

```bash
swift run
```

打包成 `.app`：

```bash
./scripts/package_app.sh
open .build/WorkHorse.app
```

## 本地数据

数据默认保存在：

```text
~/Library/Application Support/WorkHorse/
  settings.json
  tasks/
    yyyy-MM-dd.json
```

## 环境说明

当前项目使用 Swift Package Manager 构建，适合在只有 Command Line Tools 的机器上开发与验证。后续如果需要正式签名、图标资产、自动更新或上架，可以再迁移到 Xcode 工程或生成对应工程文件。

## 隐私边界

应用只保存用户主动输入的任务名称、开始/结束时间和本地设置。它不会截图、不会读取屏幕内容，也不会上传数据。
