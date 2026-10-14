# Rotation-v1 joint candidate

五张工程配套原卡的0–360°平面角度搜索候选。不是任意苹果照片分类器。用户报告当前五卡均不能识别；本文件只记录合成模型，不能代替摄像头复测。

N=256/类；ROM102400行，每行5bit，variant*400+y*20+x，bit0..4=item10..14。有效20×20来自32×32的6..25；MAX40/MARGIN24，不用±1平移。5°训练角，两基础变体再按训练残差补齐256；验证中间2.5°偏移和未用于训练的51/67/83尺寸，原28拒识逐项保存。

单独旋转bank会把圆块误作苹果，禁止脱离对称几何分流使用：卡片要求simple_shape_bits==0；块要求对应shape_ok，且paper_route抑制RGB重放。解析简单形状距离≤20，真实旋转卡最小35，负例圆形命中形状。paper_count为filtered_scene且非原始glyph阈值的点；occupied且glyph_count≥12且4*paper_count>scene_count时只走卡片。此规则不按待回答题目或卡片得分优先选类别。

旧scene-v2的truth_satisfied仅分路验收，漏了138个联立冲突/误判。本目录完整重算旧帧与最终item并保留旧证据，不修改真值。所有模型/参考一致性仍不同于实物准确率。

physical_frame采用先缩放真实卡面再旋转，硬边Alpha代表理想点采样纸边；另保留软Alpha纸边压力，不能宣称真实模糊边缘已解决。system-cases固定配方选取；refusal-cases按实际模型item核RTL，而fixtures中的物理truth仍是原卡类，不冒充识别成功。

gain0.65前后使用单位白平衡与tone07整数曲线，来自imaging候选；先抑制纸面块误路再做几何分流。透视/任意背景/硬件性能不在本模型已验证范围。
