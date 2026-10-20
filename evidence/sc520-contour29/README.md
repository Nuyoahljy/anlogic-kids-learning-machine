# T029 D0290 证据

完整RGB、逐位mask期望、原生缓存、波形和后续DB/bit留在本机，由输入/输出清单SHA绑定；Git只保存小型清单、原日志、模型报告及选定图像。不能将Git克隆当作完整迁移。

fixtures-v1的norm每词4bit：bit0=完整glyph最长边归一，bit1=色body最长边归一，bit2=色body独立宽高归一，bit3=完整glyph独立宽高归一。RTL同拍打包为{full_axis,contour_axis,contour,card}，归一化index为原32×32接口。

new-system-v1保留62原T027与140新增合成的原TruthItem；ExpectedContractItem单列已披露的未知，46个圆拒识不改标签。retained-system-v1包含182原旋转fixture和21旧场景；原始8个Truth不符（3旧黄固定颜色规则、5低光卡）保留，非全准确率。所有合成RGB都不冒称来自用户屏拍。

软件清单只汇总明确选定的完整原生正常run；注错/watchdog是RunnerGuards，旧Truth失败和未完成run单列，不混入正常通过统计。主软件接受前不启动新TD；新物理主审后另批bitgen，不自动下载或写Flash。
