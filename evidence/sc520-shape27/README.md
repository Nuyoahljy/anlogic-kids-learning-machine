# T027 软件候选证据

本目录保留旧D0261同真值失败、T027新完整场景、业务/复位/显示及边界注入测试的原始输出。新增候选为D0270，当前固定白色使用底面；合成损伤输入不是用户JPEG的逐像素重放。

每个run的run-manifest绑定实际命令、ModelSim退出码、summary、输入当前路径/快照SHA及输出SHA。选定最终软件轮次以software-v1.json为准；lifecycle中间失败及原legacy中断单独保留，不升级为通过。CSV的raw列是内部颜色锚1/4/7，D0270诊断包的RB是完成同帧唯一shape组合后的1..9公共item。

Git仅跟踪小型原始日志与清单；本机inputs快照、RGB fixtures、golden/actual像素、WLF/缓存仍在原绝对路径。跨机迁移必须按manifest保存并复核这些本机内容，Git克隆本身不包含完整仿真证据。一次性starter/setup已退役，不得重跑覆盖接续后的文件。

protected-d0261.json逐项绑定原388输入及74快照、原路由DB、旧唯一bit。软件测试通过与该保护核验均不代表新候选已过TD物理、生成bit或真实上板。主审核软件后才允许唯一新完整构建，物理审核后才另批准bitgen，不自动下载或Flash。
