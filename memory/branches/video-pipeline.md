# 分支任务：video-pipeline

- 任务 ID：`video-pipeline`
- 状态：待启动
- 负责人：main
- 分支：待创建
- 基础提交：待填写
- 开始时间：待填写
- 结束时间：待填写

## 目标与验收条件

- 目标：从 lab3 建立自研工程，验证 MIPI、ISP、DDR2、OSD 和 HDMI 基线，暴露视觉像素流 Tap。
- 验收：1280x720@60fps 稳定；DDR2 无溢出；基础 OSD 保留；视频 Tap 可输出 RGB888；接口按照 `docs/03-interface-contracts.md` 建立；短测 30 分钟通过。
- 不在范围：不实现完整积木分类、卡片模板和问答功能。

## 已读文档

- [ ] `AGENTS.md`
- [ ] `PROJECT_MEMORY.md`
- [ ] `PLAN.md`
- [ ] `TASKS.md`
- [ ] `DECISIONS.md`
- [ ] `docs/02-system-architecture.md`
- [ ] `docs/03-interface-contracts.md`
- [ ] `docs/06-test-plan.md`

## 修改文件

- 预计：`fpga/custom_project/`、`fpga/constraints/`、`fpga/sim/`、`evidence/video-pipeline/`

## 验证命令与结果

| 日期 | 命令或操作 | 预期 | 实际结果 | 结论 |
|---|---|---|---|---|
| 待填写 | 打开自研工程 | TD 6.2.1 无错误 | 待填写 | 待填写 |
| 待填写 | 综合与实现 | 无负时序余量 | 待填写 | 待填写 |
| 待填写 | 上板原始显示 | 720p60 画面正确 | 待填写 | 待填写 |
| 待填写 | 视频 Tap 仿真 | RGB888 和同步信号正确 | 待填写 | 待填写 |
| 待填写 | 30 分钟稳定测试 | 无花屏、错位、缓存溢出 | 待填写 | 待填写 |

## 证据路径

- 待填写

## 阻塞与风险

- 若 DDR2 或 HDMI 模块无法稳定，回退并使用已验证的官方模块接口。
- 接口冻结后，新增信号必须由主对话更新 `docs/03-interface-contracts.md`。

## 待决策事项

- 待填写

## 建议总文档更新

- 待填写

## 下一分支交接

- 向检测、OSD、音频和仿真分支交接冻结的接口、工程路径、模块名和测试入口。

