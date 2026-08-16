#!/usr/bin/env node
// dsh-memory-kit setup — 安装/升级记忆插件（幂等）。
// 职责：
//   1. 复制插件脚本到 ~/.dsh/memory-kit/scripts/（用户可编辑，升级不覆盖已有自定义）
//   2. 生成/合并 hooks.json（SessionStart 记忆注入 + Stop 整理检查，幂等不破坏用户已有 hook）
//   3. 初始化记忆目录模板（MEMORY.md + notes/traps.md 三档状态模板）
//   4. 依赖检测：rg（关键词搜索）；--semantic 时检测 LM Studio + bge embedding（引导用户自行安装）
// 用法：
//   dsh-memory-kit setup               # 核心安装（零依赖：记忆+踩坑库+关键词搜索）
//   dsh-memory-kit setup --semantic    # 附检测语义搜索依赖（LM Studio 由用户自行安装）
//   dsh-memory-kit setup --home <dir>  # 指定 DSH home（默认 ~/.dsh；测试用）
"use strict";
import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import os from "os";
import { fileURLToPath } from "url";

const HOME = os.homedir();
const ARGS = process.argv.slice(2);
const wantSemantic = ARGS.includes("--semantic");
const homeIdx = ARGS.indexOf("--home");
const DSH_HOME = homeIdx >= 0 ? path.resolve(ARGS[homeIdx + 1] || path.join(HOME, ".dsh")) : path.join(HOME, ".dsh");

const KIT_DIR = path.join(DSH_HOME, "memory-kit");
const SCRIPTS_DIR = path.join(KIT_DIR, "scripts");
const KIT_HOOKS = path.join(KIT_DIR, "hooks.json");
const USER_HOOKS = path.join(DSH_HOME, "hooks.json");
const MEM_DIR = path.join(DSH_HOME, "memory");
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN_SCRIPTS = path.join(__dirname, "..", "scripts");

const c = { reset: "\x1b[0m", green: "\x1b[32m", yellow: "\x1b[33m", red: "\x1b[31m", dim: "\x1b[2m" };
function ok(msg) { console.log(`${c.green}✓${c.reset} ${msg}`); }
function warn(msg) { console.log(`${c.yellow}⚠${c.reset} ${msg}`); }
function info(msg) { console.log(`${c.dim}${msg}${c.reset}`); }

// ── 1. 复制脚本 ──
function copyScripts() {
  fs.mkdirSync(SCRIPTS_DIR, { recursive: true });
  const files = ["memory-load.sh", "notes-search.sh", "session-tidy-check.sh"];
  for (const f of files) {
    const src = path.join(PLUGIN_SCRIPTS, f);
    const dst = path.join(SCRIPTS_DIR, f);
    if (!fs.existsSync(src)) continue;
    fs.copyFileSync(src, dst);
    fs.chmodSync(dst, 0o755);
  }
  // 语义搜索脚本也复制（可选能力；未装 LM Studio 时脚本会优雅降级提示）
  for (const f of ["notes-embed.sh", "notes-semantic-search.sh"]) {
    const src = path.join(PLUGIN_SCRIPTS, f);
    const dst = path.join(SCRIPTS_DIR, f);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, dst);
      fs.chmodSync(dst, 0o755);
    }
  }
  ok(`脚本已安装到 ${SCRIPTS_DIR}`);
}

// ── 2. hooks.json（插件专用 + 合并进用户 hooks）──
function memoryHooks() {
  return {
    SessionStart: [{
      matcher: "*",
      hooks: [{
        type: "command",
        command: `${SCRIPTS_DIR}/memory-load.sh`,
        timeout: 10,
      }],
    }],
    Stop: [{
      matcher: "*",
      hooks: [{
        type: "command",
        command: `${SCRIPTS_DIR}/session-tidy-check.sh`,
        timeout: 10,
      }],
    }],
  };
}

function mergeHooks() {
  // 插件自己的 hooks.json（供 cordis.patch.yml 的 configPath 指向）
  fs.writeFileSync(KIT_HOOKS, JSON.stringify(memoryHooks(), null, 2));
  ok(`插件 hook 文件已写: ${KIT_HOOKS}`);

  // 合并进用户 hooks.json（幂等：只增 memory-kit 的条目，不动已有）
  let user = { hooks: {} };
  if (fs.existsSync(USER_HOOKS)) {
    try { user = JSON.parse(fs.readFileSync(USER_HOOKS, "utf8")); }
    catch (e) { warn(`用户 hooks.json 解析失败，将新建: ${e.message}`); }
  }
  user.hooks = user.hooks || {};
  const mine = memoryHooks();
  for (const event of Object.keys(mine)) {
    user.hooks[event] = user.hooks[event] || [];
    for (const group of mine[event]) {
      const exists = user.hooks[event].some((g) =>
        JSON.stringify(g.hooks || []).includes("memory-load.sh") &&
        JSON.stringify(g.hooks || []).includes("session-tidy-check.sh") ||
        JSON.stringify(g).includes(SCRIPTS_DIR));
      if (!exists) user.hooks[event].push(group);
    }
  }
  fs.writeFileSync(USER_HOOKS, JSON.stringify(user, null, 2));
  ok(`已合并到用户 hooks: ${USER_HOOKS}`);
}

// ── 3. 记忆目录模板 ──
function initMemoryDir() {
  fs.mkdirSync(path.join(MEM_DIR, "notes"), { recursive: true });
  const idx = path.join(MEM_DIR, "MEMORY.md");
  if (!fs.existsSync(idx)) {
    fs.writeFileSync(idx, `# 记忆索引（MEMORY.md）\n每次会话开始时自动注入；最多 200 行。细节在 notes/ 对应文件，需要时 read。\n条目格式：\`- [主题](notes/<文件>.md) — 一句话摘要\`\n\n## 使用说明\n- 重要事实/用户偏好/关键决策 → 写入记忆（索引加一行 + notes/ 写文件）\n- 踩过的坑 → 写 notes/traps.md（现象/根因/防错/状态；只记失败经验不写教程）\n\n`);
    ok(`记忆索引模板已建: ${idx}`);
  } else {
    info(`记忆索引已存在，跳过: ${idx}`);
  }
  const traps = path.join(MEM_DIR, "notes", "traps.md");
  if (!fs.existsSync(traps)) {
    fs.writeFileSync(traps, `# 踩坑库（traps.md）— 犯过的错，教训 + 防错规则\n\n**纪律（Lesson ≠ Skill）**：这里**只记失败经验**（"怎么避开这个坑"），**不写怎么做事的教程**（"怎么完成任务"）——教程/技巧进别处，防止本库跑偏变脏。\n\n条目格式：现象 → 根因 → 防错 → 状态。\n**状态三档**：🆕 新鲜（刚踩，防错未实战验证）/ ✅ 已验证（防错起效，= 该坑已实测有效）/ ⬆️ 已升级（同类犯 2 次，规则进 AGENTS.md）\n**证据等级（可选标注）**：亲历（自己踩过）/ 查证（看文档/代码确认根因）/ 推断（未完全验证的猜测）——帮后续判断可信度；能标就标，不强制。\n\n---\n`);
    ok(`踩坑库模板已建: ${traps}`);
  }
}

// ── 4. 依赖检测 ──
function checkRg() {
  try {
    execFileSync("rg", ["--version"], { stdio: "ignore" });
    ok("rg 已安装（关键词搜索可用）");
    return true;
  } catch (_) {
    warn("未检测到 rg（ripgrep）——关键词搜索需要它");
    info("  安装: brew install ripgrep   (macOS)");
    info("        sudo apt install ripgrep (Linux)");
    return false;
  }
}

function findLms() {
  // 跨平台探测：macOS/Linux 与 Windows（含 Git-Bash 环境）
  const candidates = [
    path.join(HOME, ".lmstudio", "bin", "lms"),
    process.env.USERPROFILE ? path.join(process.env.USERPROFILE, ".lmstudio", "bin", "lms") : null,
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Programs", "LM Studio", "bin", "lms") : null,
    path.join(HOME, "AppData", "Local", "Programs", "LM Studio", "bin", "lms"),
  ].filter(Boolean);
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

function checkLmStudio() {
  const lms = findLms();
  if (lms) {
    ok("LM Studio 已安装（语义搜索/视觉可用）");
    // 检测 embedding 模型
    try {
      const out = execFileSync(lms, ["ls"], { timeout: 20000 }).toString();
      if (/bge|embed/i.test(out)) ok("embedding 模型已就绪（bge/nomic）");
      else warn("LM Studio 已装但未发现 embedding 模型（语义搜索暂不可用）");
    } catch (_) {
      warn("LM Studio 已装但 CLI 调用失败（可能未初始化，先开一次 GUI）");
    }
    return true;
  }
  warn("未检测到 LM Studio（语义搜索与视觉能力不可用）——由用户自行安装");
  info("  1. 到 lmstudio.ai 下载安装");
  info("  2. 打开一次 LM Studio（完成初始化）");
  info("  3. 下载 embedding 模型 bge-small-zh-v1.5（语义搜索，25MB）");
  info("  4. 视觉识图另需 Gemma 4 等多模态模型（18GB，可选）");
  info("  5. 装好后重跑: dsh-memory-kit setup --semantic");
  return false;
}

// ── 主流程 ──
console.log(`\ndsh-memory-kit setup → ${DSH_HOME}\n`);
copyScripts();
mergeHooks();
initMemoryDir();
console.log("");
const rgOk = checkRg();
console.log("");
if (wantSemantic) checkLmStudio();
else {
  info("语义搜索为可选能力（需 LM Studio + bge embedding，由用户自行安装）");
  info("需要时跑: dsh-memory-kit setup --semantic 检测");
}
console.log("");
ok("setup 完成。能力状态：");
console.log(`  记忆注入      ✓ 已配置（SessionStart）`);
console.log(`  踩坑库        ✓ 模板已建`);
console.log(`  关键词搜索    ${rgOk ? "✓" : "✗ 装 rg 后可用"}`);
console.log(`  语义搜索      ${wantSemantic ? "见上方检测结果" : "可选，未检测（--semantic）"}`);
console.log(`  视觉识图      ${wantSemantic ? "见上方检测结果" : "可选（需 LM Studio + 多模态模型）"}`);
console.log(`\n重启 DSH（或新开会话）后生效。\n`);
