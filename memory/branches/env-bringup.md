# 分支任务：env-bringup

- 任务 ID：`env-bringup`
- 状态：待启动
- 负责人：board-holder
- 分支：待创建
- 基础提交：待填写
- 开始时间：待填写
- 结束时间：待填写

## 目标与验收条件

- 目标：完成 TD 6.2.1、License、驱动、下载器识别和 lab1 上板，并保存完整复现步骤。
- 验收：TD 版本为 6.2.1；AL-LINK-FT 识别 PH1P35MDG324；官方预编译 bit 显示 1280x720@60fps；lab1 从短英文路径重新编译成功；记录时序和资源报告。
- 不在范围：不开发视觉、OSD、音频和问答功能。

## 已读文档

- [ ] `AGENTS.md`
- [ ] `PROJECT_MEMORY.md`
- [ ] `PLAN.md`
- [ ] `TASKS.md`
- [ ] `DECISIONS.md`
- [ ] `docs/03-interface-contracts.md`
- [ ] `docs/06-test-plan.md`
- [ ] `docs/07-risk-register.md`

## 修改文件

- 仅允许任务卡指定的 `fpga/vendor_labs/lab_ex1/`、`hardware/env-bringup/`、自身日志和 `evidence/env-bringup/`；不修改共享 hardware 文档或原始例程。
- 先读 hardware/first-bringup.md；填写记录副本放 evidence/env-bringup/runs/<run-id>/，保留空白模板。

## 验证命令与结果

| 日期 | 命令或操作 | 预期 | 实际结果 | 结论 |
|---|---|---|---|---|
| 待填写 | 查看 TD 版本 | 6.2.1 | 待填写 | 待填写 |
| 待填写 | AL-LINK-FT 扫描 | 识别 PH1P35MDG324 | 待填写 | 待填写 |
| 待填写 | 烧录 lab1 预编译 bit | 720p60 原始画面 | 待填写 | 待填写 |
| 待填写 | 重新综合与布局布线 | 生成 bit，时序无负余量 | 待填写 | 待填写 |
| 待填写 | 连续显示 30 分钟 | 无花屏、错位或阻塞 | 待填写 | 待填写 |

## 证据路径

- 待填写

## 阻塞与风险

- 驱动签名、内存完整性、BitLocker 或 WinUSB 的任何改变必须事前用户确认，再逐步记录；默认不关闭安全保护。
- 原始工程只在确认来源/许可/归属后还原到任务卡允许的短 ASCII 项目目录；不直接改 E:/juan/FPGA/anlogic_2026 的既有副本或另一人的构建输出。

## 待决策事项

- 待填写

## 建议总文档更新

- 待填写

## 下一分支交接

- 向 `video-pipeline` 交接已验证的 TD 工程、时钟约束、摄像头配置和 bit 烧录流程。
