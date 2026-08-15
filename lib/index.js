// dsh-memory-kit — host 面插件入口
// 职责：声明插件行（供 cordis 挂载），核心记忆注入/检索靠 hooks（SessionStart 注入
// 记忆索引 + Stop 整理检查），本文件只做轻量声明——hook 脚本由 setup 生成到
// ~/.dsh/memory-kit/，插件升级不影响用户数据（记忆在 ~/.dsh/memory/）。
export const name = 'dsh-memory-kit'

export function apply(ctx) {
  // hooks-claude-code 由 cordis.patch.yml 插入并接管 SessionStart/Stop；
  // 这里留空占位：未来若需注册 memory_* 工具（读/写/搜索记忆）在此扩展。
}
