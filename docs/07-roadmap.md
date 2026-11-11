# 开发计划

本文说明已经完成了什么、计划做什么。计划中的事项都不带日期。产品定位见 [01-vision](./01-vision.md)。

## 原则

1. **先有能玩的东西,再扩充数量。** 启动器和现有三款游戏的完整流程(选游戏、开局、暂停、结算、记录、成就)先做扎实,新游戏接在同一套流程上。
2. **内容必须原创。** 可以做经典类型,不复刻现有商业游戏的名称、角色、美术或关卡([ADR-016](./decisions.md))。
3. **守住 GameSession 边界。** 启动器与 Runtime 只经 `runtime/game_session.gd` 通信,新游戏不得绕过它([ADR-003](./decisions.md))。
4. **如实呈现。** 界面只显示真实的记录;文档和官网只写代码里已经有的东西。

## 已完成

**启动器**(`apps/client/launcher`,客户端主场景):

- [x] 首页、游戏库(分类、排序、搜索、收藏)、成就。
- [x] 设置:语言(中文 / English)、窗口模式、垂直同步、帧率上限、音量、键盘改键、存档导出导入与清除。
- [x] 游戏流程:单款游戏的菜单、局内 HUD、暂停、结算,每局恰好记录一次。
- [x] PC 模式:面向键盘鼠标的另一种布局,F11 或长按 View 切换。
- [x] 键盘、手柄、鼠标三种输入,手柄方向连发。
- [x] 单一本地存档,不联网。
- [x] 无头测试门禁:`make launcher-test`、`make settings-test`、`make library-test`、`make launch-test`、`make pc-mode-test`、`make game-flow-test`,均在 `make ci` 内。

**游戏**(各是 `apps/client/runtime` 下的一个 Runtime,运行自带的基线 DSL):

- [x] 星环巡航 / Orbit Patrol(`shooter`,飞行射击)。
- [x] 长夜草原 / Meadow Vigil(`survivor`,生存动作)。
- [x] 隘口守卫 / Gatewatch(`tower_defense`,塔防)。
- [x] 三款游戏共 11 个成就,各有一张主视觉。

**Mod DSL 与可选的在线服务**(保留,启动器没有接入):

- [x] 三个 Runtime 的版本化 schema 与基线,RFC 6902 补丁与迁移的 Go、GDScript 两份实现,由共用的基线和 golden 文件做一致性测试。
- [x] Go 后端(账号、目录、Mod、社区、商业化等 API,AI 生成 DSL 补丁)、命令行 `classic-games`、MCP 服务 `classic-games-mcp`、Go SDK,各有测试。

**客户端清理**:

- [x] 移除客户端里的手机应用壳(信息流、AI 创作流程、社区、商业化、账号等界面及其测试)。

## 当前的已知不足

这些是现状,不是承诺:

- 局内画面是几何图形,没有贴图美术。
- 只有 Shooter 有程序合成的背景音乐,没有任何游戏播放音效。
- 三款游戏都只支持单人。
- 没有公开的构建,只能从源码用 Godot 4.6.3 运行。

## 计划中

计划加入以下类型的原创游戏,没有日期,顺序也未确定:

- 基地防御坦克
- 横版平台跳跃
- 合作平台跳跃
- 迷宫炸弹
- 合作清版街机
- 跑动射击

每一款都使用原创的名称、角色、美术和关卡。新增一款游戏需要的改动见根目录 [CONTRIBUTING](../CONTRIBUTING.md) 的「Adding a game or a runtime」。

## 没有计划的事项

- **启动器接入在线服务。** 后端、CLI、MCP 与 SDK 作为可选组件保留在仓库里,但没有把启动器接到它们上面的计划;要做需要单独的产品决策。
- **在启动器里恢复 Fork、AI 创作、社区或付费界面。**

## 决策变更(2026-11-11)

本文此前是「AI Mod 创作社区」的分阶段计划:Phase 0 技术 spike(中文 IME、虚拟列表、5 端导出、AI → DSL 打通、创造感盲测、裸 PGC 留存),Phase 1 验证「玩 → AI 改 → 发布 → Fork」闭环(目标 100 用户 / 1000 Mod / 500 Fork),Phase 2 增加 Survivor 与 Tower Defense 并补全社交,Phase 3 做联机、AI 自动平衡与结构生成、创作者经济。

2026-11-11 产品改为主机风格启动器([ADR-016](./decisions.md)),上述分阶段计划随之停止。停止时的状态:

- DSL schema 地基、GameSession 边界、RuntimeLoader、三个 Runtime、AI → DSL 的服务端链路已经完成,并保留在现在的代码里。
- 中文 IME 真机实测、虚拟列表原型、5 端真机导出、创造感盲测、裸 PGC 留存这几项决策门没有完成。其中 IME 与长列表针对的是手机应用壳,随它一起不再相关。
- 服务端的联机房间、AI 平衡、结构生成、创作者经济等能力留在可选的在线服务里,启动器没有使用。
