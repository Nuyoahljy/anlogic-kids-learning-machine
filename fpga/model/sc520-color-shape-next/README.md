# SC520 固定 RGB 颜色模型 v1

本模型用于后续红黄蓝颜色形状候选的独立颜色实验，尚未接生产管线，也不构成几何识别、RTL 整机、时序、bit 或硬件通过。

评分前固定的整数规则如下，未根据旧样本结果调整参数：

- `max(R,G,B) < 32` 或 `max-min < 24` 时拒绝颜色资格。
- 红色：`R > 2G` 且 `R > 2B`。
- 蓝色：`B > 2R` 且 `B > 2G`。
- 黄色：`min(R,G) >= 2B` 且 `max(R,G) <= 2*min(R,G)`。
- 其他 RGB 为未知。

完整 glyph 内只接受唯一主色，要求 `3*winner >= 2*glyph_pixels`，且主色票数至少为其他每种颜色的两倍。未知颜色像素仍进入 glyph 分母。两项票数门槛允许等号；像素红/蓝的两倍关系使用严格大于。

`evaluate.py` 只依赖 Python 标准库，以旧 `scene-model.py` 相同中心位置采样既有320×180 `.rgb.mem` 输入。本实验用“RGB不等于边框众数”作为颜色诊断 mask，**不是生产 scene 的真实完整 glyph 提取器**。报告保存全部输入 SHA-256、16个固定 RGB 向量、12个投票边界向量和62个旧样本的逐例结果，不推断 shape。

`clipped` 行是明确限制：颜色阶段可能得到红色资格，因为它不消费裁剪、完整轮廓或健康元数据。该行保留源真值0；报告中的未评分 `Pass=true` 不能解释为安全负例通过。后续使用颜色结果前，上游必须拒绝裁剪、不完整、不健康或过期 glyph。

在本 Worktree 内运行，输出选择新的 run-id：

```powershell
python -I -B fpga/model/sc520-color-shape-next/evaluate.py --run-id another-run
```

输出位于 `evidence/sc520-color-shape-next/model-v1-another-run/`，非空目录拒绝覆盖。当前代码 E0B5812E 的准确报告是 `model-v1-current-20261029-1118`；旧 `model-v1` 和 `model-v1b` 绑定05C84576历史脚本，保留旧身份，不冒称由当前代码执行。
