# 分支任务：system-integration

- 任务 ID：`system-integration`
- 状态：待启动
- 负责人：main
- 分支：待创建
- 基础提交：待填写
- 开始时间：待填写
- 结束时间：待填写

## 目标与验收条件

- 目标：把视频、积木检测、卡片检测、OSD、音频、按键和计分合并成单个上电自动运行的镜像。
- 验收：单项功能全部保留；探索模式 2 秒内反馈；问答 10 题正确；帧号和延迟显示；单 bit 冷启动；无负时序余量。
- 不在范围：不在本分支增加新算法或改变已冻结接口。

## 已读文档

- [ ] `AGENTS.md`
- [ ] `PROJECT_MEMORY.md`
- [ ] `PLAN.md`
- [ ] `TASKS.md`
- [ ] `DECISIONS.md`
- [ ] `docs/01-product-spec.md`
- [ ] `docs/02-system-architecture.md`
- [ ] `docs/03-interface-contracts.md`
- [ ] `docs/06-test-plan.md`

## 修改文件

- 预计：`fpga/custom_project/top/`、`fpga/constraints/`、`fpga/release/`、`evidence/system-integration/`

## 验证命令与结果

| 日期 | 命令或操作 | 预期 | 实际结果 | 结论 |
|---|---|---|---|---|
| 待填写 | 全工程综合与实现 | 生成单 bit，时序合格 | 待填写 | 待填写 |
| 待填写 | 探索模式 | 2 秒内文字和语音反馈 | 待填写 | 待填写 |
| 待填写 | 问答模式 | 连续 10 题正确 | 待填写 | 待填写 |
| 待填写 | 帧号与延迟 | 显示数值且可解释 | 待填写 | 待填写 |
| 待填写 | 冷启动 | 断电重上电自动恢复 | 待填写 | 待填写 |

## 证据路径

- 待填写

## 阻塞与风险

- 任何超限或时序负余量都回到对应模块修复，不在顶层通过降低功能绕开。

## 待决策事项

- 待填写

## 建议总文档更新

- 待填写

## 下一分支交接

- 向 `verification-submission` 交接候选发布 bit、提交号和已知问题。

