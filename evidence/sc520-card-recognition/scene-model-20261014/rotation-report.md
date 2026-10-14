# 五卡全角度搜索与联合场景模型交接

日期：2026-10-14。基础3089ae8，当前工作树task/sc520-card-recognition；本子任务未自行提交Git，由父任务统一集成、日志和提交。

用户最新确认使用工程附带的五张原卡，当前五张全部无法识别；并要求区内平移、尺寸变化及0～360°平面旋转。现场失败是用户报告。本报告未获取新的SC520照片，也没有上板或硬件通过结论。

## 冻结候选

`assets/templates/sc520-card-recognition/rotation-v1/templates.mem`：每类256模板、102400地址×5bit，地址`variant*400+y*20+x`，bit0..4是item10..14。20×20取32×32 mask的6..25。MAX_DISTANCE=40、MIN_MARGIN=24，无±1平移。SHA256：731EC1B57D12F2EF305C35A055169BCD6733A4F76836AD1FA278BEE5BD9E8341.

旋转训练5°间隔，训练48/64/80/96 bp像素和四相位，包含先旋转再缩放与先缩放再旋转两个渲染顺序。每角2基础变体，再按训练残差最远优先补齐256，不把评价图加入模板。开发设计比较20°、15°、10°、5°与3°、4°密度，全部证据保留在rotation-design-20261014与rotation-design-dense-20261014。选择设计时看过这些结果，因此属于开发评测，不是盲测。

## 定量结果和边界

独立于训练角度的2.5°偏移、51/67/83尺寸×四采样相位共4320条，4292识别正确、28保守拒识、0错类。每个角度跨0～360°全周搜索，但不保证任意实拍100%。

| 类别 | 正确 / 总数 | 拒识 | 最差距离 | 最小类间margin |
|---|---|---|---|---|
| apple | 862 / 864 | 2 | 45 | 35 |
| banana | 864 / 864 | 0 | 34 | 32 |
| car | 849 / 864 | 15 | 45 | 42 |
| star | 864 / 864 | 0 | 39 | 38 |
| umbrella | 853 / 864 | 11 | 47 | 29 |

全角度bank本身会把圆形当苹果，裸bank禁止单独作为已验收识别器。158个负例里27个圆块和3个未知灰圆在MAX40已经被apple接受，best29～35；加到44/48仍重叠。±1格平移只救15/28拒识且有相同圆误判，已放弃，未进入冻结候选。

加入明确互斥的几何证据：卡片必须simple_shape_bits==0；积木必须通过对应shape bit。简单圆/方/直立三角形解析模板Hamming≤20才算通过；4320张旋转真卡到任何简单形状最小距离依次35/105/94/84/100，没有被这条排除。原138个纸卡/伪块冲突全部被纸面路由和对应轮廓证明解决。paper_count为filtered_scene且不满足原始glyph阈值的像素；occupied、glyph≥12、4×paper_count>scene_count时积木重放全白，卡片mask保留、present不清除。

旧scene-v2的653个定义范围完整重新按最终item验证，653/653；新完整RGB固定system清单69例最终真值全符合，包括五卡0/90/180/270与中间角、不同摆位、九块、未知灰圆、框外/边界与tone后五卡。另有不同尺寸/角度的额外完整RGB例，实际结果全保留。软纸边只测了少量合成例，不能保证现实模糊纸边。

28个原拒识已另存`evidence/sc520-card-recognition/rotation-refusals-20261014`，每例按真实frame (41+2x,31+2y)与粘贴位置逆奇偶匹配原相位；28/28完整RGB与dense五类距离完全相等且全部实际拒识。原rotation-v1里那批相位相反的replay实际通过，保持原文件和实际结果；它不能作为28条原拒识的复现证据。拒识目录的system-cases按实际item0验证RTL，fixtures中的物理truth仍是原卡类，没有改标签。

## 暗沉对照

同一五卡gain0.65使纸白255→165，旧绝对glyph阈值把纸面当图案，五卡全拒。单位WB的tone07将165→188，加入纸面路由/形状分流后五卡最终item10～14全正确。tone曲线全部256输入点与成像任务实际RTL核对一致（该任务把常数乘改写为移位加法，数值不变）。成像SHA见rotation-checks.json。色彩链路的新RTL与实际摄像头照片仍由父任务验证，这些像素变换不能证明实物暗沉已经解决。

## 实际命令和证据

以下均用bundled Python -B -X utf8在本工作树执行：

- `experiment-scene-rotation.py --output evidence/sc520-card-recognition/rotation-design-20261014`：8组角度/模板数对比完成。
- `experiment-scene-rotation.py --output evidence/sc520-card-recognition/rotation-design-dense-20261014 --steps 3 4 5 --variants 2 --budget 256 --dual-order`：3组256模板比较完成。每轮有冻结脚本输入或补存的相同SHA原件。
- `generate-rotation-fixtures.py`：exit0；生成冻结模板、69个system真值清单、业务三名、完整RGB及联合报告。
- `export-rotation-refusals.py`：exit0；28条采样相位及完整RGB拒识逐项重现。
- `test-rotation-model.py --report evidence/sc520-card-recognition/scene-model-20261014/rotation-checks.json`：exit0，741检查0失败；覆盖全部主资产/拒识资产哈希、输入快照、ROM布局、69系统真值、业务三名、4320无错类与28拒识、旧653最终仲裁、几何排除、精确相位及tone全部256点。

模型源为scene-rotation-model.py；scene-model.py及scene-v2生成器保持原字节，因此旧v2仍可复现。形状规则与imaging_audit独立block_shape_model.py一致；场景RTL由scene_rtl负责，串行旋转matcher、系统集成和资格由父任务负责。本报告不代替其结果。
