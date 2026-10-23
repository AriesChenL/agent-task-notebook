# Agent Notebook

本地 Mac 桌面任务记事本。把 Claude Code、Codex 和其他 Agent 的任务、会话名称、工作目录、进展和下一步放在一起。原生 SwiftUI，macOS 14+，无第三方运行依赖。

## 启动

```sh
scripts/build-app.sh
open 'dist/Agent Notebook.app'
```

可以把生成的 `.app` 复制到 Applications 使用。当前为本机 ad-hoc 签名构建，未做 Apple 公证或跨架构分发。

## 功能

- 当前任务、全部任务和四种状态筛选；搜索名称、进展、目录、工具及会话。
- 创建、编辑、删除任务；记录目标、最新进展、下一步、分支及 PR。
- 每个任务关联多个会话：工具、名称、ID、链接、职责、目录。
- Finder 打开目录、打开已填写的会话或 PR 链接、复制任务 ID。
- 约 2 秒刷新 CLI 写入；保留活动记录。详情显示最近 30 条，CLI 输出完整历史。
- 多进程文件锁、原子写入、桌面乐观锁，避免静默覆盖。

状态由用户或 Agent 主动更新，不会自动扫描或控制 Claude Code/Codex，不会凭会话名称推测会话链接。第一版无云同步、任务依赖和系统通知。

## CLI

```sh
scripts/install-cli.sh
# 如果 ~/.local/bin 不在 PATH，可直接调用 ~/.local/bin/tasknote
~/.local/bin/tasknote --help
~/.local/bin/tasknote add --title '修复登录' --status running --directory '/path/to/repo'
~/.local/bin/tasknote list
~/.local/bin/tasknote session add <任务ID> --tool 'Claude Code' --name '修复登录' --role '实现' --session-id '<工具里的会话ID>'
~/.local/bin/tasknote update <任务ID> --progress '已修复，测试通过' --status waiting --next '请验收'
~/.local/bin/tasknote note <任务ID> --text '补充一条进展'
~/.local/bin/tasknote show <任务ID>
```

`add/update` 支持 `--title --goal --status --directory --branch --pr --progress --next`。
状态值：`todo / running / waiting / done`。会话工具名称为自由文本。
`session add` 支持 `--tool --name --session-id --link --role --directory`。
`session remove <任务ID> --id <关联记录ID>` 移除会话关联。任务删除在桌面中确认执行。
JSON 输出适合 Agent 读取；失败退出码 1，错误进入 stderr。使用完整任务 UUID。

可给 Agent 的指令：

> 使用 ~/.local/bin/tasknote 管理本次任务。开始时创建或找到已有任务，登记你的工具、会话名称和工作目录；在重要进展后更新 progress，需要我介入时设 waiting 并写清 next，真正完成后设 done。不要编造未知会话 ID 或链接。

## 数据与恢复

默认数据：`~/Library/Application Support/TaskNotebook/tasks.json`。
`tasknote path` 可查询路径。设置 `TASKNOTE_HOME` 可隔离测试数据；桌面与 CLI 必须使用相同目录才会共享数据。数据以本地 JSON 明文存储，请勿填写密钥。

备份时关闭应用并停止 CLI 写入，再复制 `tasks.json`。恢复同理。损坏或不支持的数据版本会报错，不会自动覆盖。更新前建议备份；删除任务不可撤销。桌面保存遇到冲突时保留编辑内容，复制需要保留的文字后取消并重新编辑。

## 验证

```sh
swift test
python3 scripts/smoke-cli.py
```

覆盖持久化、并发更新、版本冲突、损坏数据保护及 CLI 多进程读写。

## 自定义标签

在任务编辑页输入标签，用中文或英文逗号分隔；点击添加或直接保存。可移除标签或选择已有标签。侧栏按标签筛选，搜索也匹配标签。标签名称忽略首尾空白，同一任务内不区分大小写去重。

```sh
tasknote update <任务ID> --tags '后端,紧急'
tasknote list --tag '后端'
tasknote update <任务ID> --tags ''
```

`--tags` 替换该任务的全部标签，不传则保留。旧数据缺少标签字段时按空列表读取。

## 开始时间、结束时间与时间线

编辑任务中的“任务时间”可以分别启用开始、结束时间，精确到分钟，也可以取消设置。结束不能早于开始。任务状态不自动修改时间，旧任务默认未设置。

顶部“时间线”切换到甘特式图表，跟随当前状态、标签及搜索筛选。横条显示时间跨度，颜色对应状态，点击查看详情。只有一个时间的任务显示圆点，两者都没有的任务单列在“未设置时间”中。界面使用系统时区；CLI 要求显式时区。

```sh
tasknote update <任务ID> --start '2026-10-23T09:00:00+08:00' --end '2026-10-23T18:00:00+08:00'
tasknote update <任务ID> --end ''
```

不传参数保留原值，传空字符串清空。`show/list` 输出 ISO 8601 UTC 时间。

### 组合筛选

任务列表顶部可选择标签，并启用“按时间筛选”设置起止日期。列表与时间线同步使用筛选结果，可与侧栏状态、标签及搜索叠加（取交集）。时间筛选包含截止日期的全天，按系统时区计算；完整时间段按重叠匹配，仅一个端点按该时刻匹配，未设置时间则排除。支持一键清除时间与标签筛选。

## 卡片式工作台

主界面采用侧栏和自适应任务卡片网格。卡片展示状态、任务名、最新进展、Agent 工具、标签和起止时间；底部可复制工作目录、直接编辑。点击卡片打开详情浮层，点击外部关闭。

顶部集中提供搜索、标签、时间筛选以及卡片/时间线切换。时间线点击任务同样打开详情，关闭详情后保留原视图和筛选。编辑未保存时关闭会先提示放弃修改。

本次验证：7 项数据测试、CLI 冒烟及跨进程并发更新通过；真实桌面确认卡片布局、搜索结果、详情打开/外部关闭和时间线跳转。任务数据未作为示例上传仓库。
