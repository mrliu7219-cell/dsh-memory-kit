# dsh-memory-kit

给 DeepSeek Harness（DSH）装上持久记忆和学习循环的插件——会话开始自动注入记忆索引，踩过的坑沉淀进踩坑库，关键词/语义双通道检索，越用越聪明。

**平台**：macOS / Windows（Git-Bash 环境）✅ 核心功能跨平台；语义搜索需本机 LM Studio（两平台均支持，路径自动探测）

## 能力（三档，按需启用）

| 能力 | 依赖 | 说明 |
|---|---|---|
| **记忆注入** | 零依赖 | SessionStart 自动注入 MEMORY.md 索引，notes/ 按需读取 |
| **踩坑库** | 零依赖 | traps.md 三档状态（🆕新鲜/✅已验证/⬆️已升级）+ Lesson≠Skill 纪律（只记失败经验）+ 可选证据等级标注，犯 2 次升级 AGENTS.md |
| **关键词搜索** | rg（可先装） | `notes-search.sh <词>`，19ms 全文检索 |
| **语义搜索**（可选） | LM Studio + bge-small-zh | `notes-semantic-search.sh <描述>`，本地 embedding 不联网 |
| **视觉识图**（可选） | LM Studio + 多模态模型 | 需另配 modlens 等视觉插件，本插件不内置 |

核心设计：**文件是真相，向量是索引**——记忆全是 Markdown 文件，可读可改可备份；语义搜索只是可重建的辅助层。

## 安装

```bash
# 1. 装插件（dependencies 会自动拉取 hook 协议包）
dsh plugin --profile <你的profile> add dsh-memory-kit

# 2. 初始化（复制脚本 + 配置 hook + 建记忆目录模板）
dsh-memory-kit setup

# 3. （可选）想要语义搜索时，先自行安装 LM Studio 并下载 bge-small-zh-v1.5，然后：
dsh-memory-kit setup --semantic
```

重启 DSH（或新开会话）生效。

> **注**：`dsh plugin add` 若用本地路径（link 模式）安装，依赖不会自动拉取，需手动
> `dsh plugin --profile <p> add @deepseek-ai/dsh-hooks-claude-code @deepseek-ai/dsh-hook-protocol`。
> 从 npm registry 安装则无此问题。

## 使用

会话开始自动注入记忆索引。日常：

- **记住什么**：重要事实/用户偏好/关键决策 → 更新 MEMORY.md 索引 + notes/ 文件
- **踩坑了**：写 notes/traps.md（现象 → 根因 → 防错 → 状态）
- **找旧知识**：`notes-search.sh <关键词>`（精确）；`notes-semantic-search.sh <描述>`（语义）
- **维护**：索引接近 200 行时合并精简；向量索引变了跑 `notes-embed.sh` 增量刷新

## 记忆目录

```
~/.dsh/memory/          # 记忆本体（可配置 MEMORY_DIR 环境变量）
├── MEMORY.md           # 索引（≤200 行，会话开始注入）
├── notes/              # 细节笔记（按需 read）
│   └── traps.md        # 踩坑库
└── .vector-index.json  # 向量索引（可重建，非真相）
```

## 设计原则

- **文件是真相**：记忆是纯 Markdown，删掉向量索引零损失
- **优雅降级**：没 LM Studio 照样工作（关键词搜索），语义搜索是可选项
- **不碰用户配置**：hook 配置独立文件，setup 幂等合并，不覆盖用户已有 hook
- **本地优先**：embedding 全本地，数据不上云

## 与其他记忆方案的差异

| 方案 | 定位 | 与 dsh-memory-kit 的差异 |
|---|---|---|
| **Basic Memory**（Claude 生态） | Markdown + SQLite 知识库 | 两者理念相近（文件是真相）；本插件专为 **DSH** 设计（cordis patch + hooks 集成），且内建**踩坑库三档升级机制**（犯错→沉淀→升级常驻规则） |
| **deep-memory**（Claude Code） | 向量库自动积累经验 | 它依赖 ChromaDB + BGE 重排，个人量级是过度工程；本插件零重依赖，语义搜索仅需 25MB 本地模型且**可完全不用** |
| **Mem0 / Letta** | 抽取式记忆层/状态化 agent | 需要额外 LLM 调用做抽取（成本+不可控）；本插件"用户/agent 直接写文件"，可控、可审查、零抽取成本 |
| **知识图谱类**（Neo4j MKG 等） | 实体关系检索 | 个人笔记实体关系稀疏，建图收益趋近 0；本插件用"索引+全文/语义双检索"覆盖 90% 场景 |

**选择本插件的理由**：如果你要的是**一套轻量、透明、能带着历史越用越聪明的 DSH 记忆系统**，而不是一个需要数据库和额外 LLM 成本的记忆平台。

## 升级

```bash
dsh plugin --profile <你的profile> update dsh-memory-kit
dsh-memory-kit setup          # 重新生成脚本与 hook（记忆数据不受影响）
```

## License

MIT
