# dsh-memory-kit 开发日志

> 项目级持久记录：每次开发/发布/重要决策追加一行，只记新增事实。
> 配合记忆笔记 `~/.dsh/memory/notes/dsh-memory-kit.md`（项目状态全貌）使用。

## 2026-08-16

### v0.1.0 — 首发（完成）
- 从本机记忆系统产品化为 DSH 插件：记忆注入 + 踩坑库三档 + 关键词/语义双检索
- 结构：package.json（dsh.bundle）+ cordis.patch.yml（!!js 动态 HOME）+ lib/{index,setup}.js + scripts/×5
- setup 一键安装：脚本复制 + hook 幂等合并 + 记忆目录模板 + 依赖检测
- 优雅降级：无 LM Studio 时语义搜索给引导不报错
- 隔离测试全过：setup/注入/搜索/降级/boot（临时 DSH_HOME，未碰生产）
- 踩坑（记入 traps.md）：ESM/CommonJS 冲突、pnpm 10 严格 peer 依赖、link 安装不拉依赖

### v0.1.1 — 跨平台支持（完成）
- 移除 macOS 专属 `stat -f` 死代码（换跨平台 `find -newer`）
- LM Studio CLI 路径自动探测：macOS/Linux + Windows Git-Bash（USERPROFILE/LOCALAPPDATA）
- 修复 `set -u` 下未定义变量报错（`${VAR:-}`）
- 回归测试：降级场景干净 + 真实场景语义搜索正常

### 发布与社区（完成）
- GitHub 公开仓库：mrliu7219-cell/dsh-memory-kit（描述 + 5 主题标签）
- 标签：v0.1.0、v0.1.1
- 社区帖：#2147（Show Your Plugins!），含跨平台更新评论
- README：加"与其他记忆方案差异"对比章节

## 待办（未定节奏）
- [ ] npm 发布（等 GitHub 反馈或自己用稳）
- [ ] 真实用户安装反馈收集
