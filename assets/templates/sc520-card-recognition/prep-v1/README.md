# 五卡软件模型数据

状态：软件模型与RTL接口候选，尚未相机模板验收。

原稿为 `learning/sc520-next-stage-prep/cards/` 的 prep-v1 五个 SVG，本脚本只读输入，逐个记录源哈希。
`templates-preview.png` 上排为 256×256 渲染，下排为 32×32 二值模板放大图。

- 二值条件：`min(R,G,B)<180 || max(R,G,B)-min(R,G,B)>=40`。前景为1、背景为0。
- 模板点：256图的 `(8*gx+4,8*gy+4)`；按行存储，`templates.mem` bit0..4对应10..14。
- RGB激励：320×180帧，ROI左上角(96,26)、128×128；每格4像素、中心偏移2。
- canonical ROI每个像素(x,y)取256图的(2x,2y)，精确对应模板采样点。这里没有用双线性缩小，也没有相机过程。
- 比较：1024位Hamming距离；`best<=120`、`second-best>=24`、前景16..850才输出候选ID；否则0。
- 距离平局的候选暂选较小ID，仅作为调试信息；margin=0使最终结果拒识。

## 文件接口

`vectors.json`给每个样本输入文件、真实语义标签和软件模型输出。`ground_truth_item_id=0`表示负样本。模型输出不是语义标签。
`vectors/*.rgb.mem`是128×128 ROI，共16384行，RGB888十六进制RRGGBB；帧其余像素填FFFFFF。
`vectors/*.bits.mem`是32×32采样，共1024行0或1。`vectors.meta.mem`每样本8个32位hex：index、truth、candidate、accepted、best、second、sample_fg、roi_fg。
`vectors-files.vh`放入Verilog initial块，预先声明vector_rgb_file和vector_bits_file数组；路径相对数据集根目录。`vectors-count.vh`定义CARD_VECTOR_COUNT。

## 本组模型结果

```json
{
  "total": 69,
  "canonical": {
    "correct_accept": 5
  },
  "synthetic_variations": {
    "correct_accept": 44,
    "reject": 6
  },
  "negatives": {
    "reject": 11,
    "false_accept": 3
  },
  "by_category": {
    "canonical": {
      "correct_accept": 5
    },
    "shift_one_cell": {
      "correct_accept": 20
    },
    "rotate": {
      "correct_accept": 10
    },
    "brightness": {
      "reject": 5,
      "correct_accept": 5
    },
    "salt_pepper_noise": {
      "correct_accept": 5
    },
    "half_occlusion": {
      "reject": 1,
      "correct_accept": 4
    },
    "negative_blank": {
      "reject": 1
    },
    "negative_black": {
      "reject": 1
    },
    "negative_geometry": {
      "false_accept": 3,
      "reject": 6
    },
    "negative_mix": {
      "reject": 1
    },
    "negative_unknown": {
      "reject": 1
    },
    "negative_unsampled": {
      "reject": 1
    }
  }
}
```

每项结果见 `model-report.json`、`vectors.json`。测试不强迫所有扰动被识别；预期值用于比较RTL是否与这个明确模型一致。

## 复现

使用已有Pillow的Python与已有sharp的Node，不下载或安装依赖。输出目录必须不存在，失败目录保留；新运行请换目录名。

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' `
  fpga/scripts/sc520-card-recognition/generate-templates.py `
  --source E:/juan/FPGA/learning/sc520-next-stage-prep/cards `
  --output assets/templates/sc520-card-recognition/new-run
```

程序从bundled Python的相邻dependencies目录寻找Node和sharp，也可显式传入`--node`、`--node-module-root`。软件版本、源输入及输出哈希见`generation.json`和`manifest.json`。

## 边界

- Canonical与模板同源，只证明坐标/序列/接口一致，不属于独立准确率。
- 平移、旋转、亮度、噪点和遮挡均为人工变换；这些结果不代表相机/打印/摆放实测。
- 不执行位移搜索、尺度归一化、透视校正或相机白平衡校准。
- min RGB<180将暗灰白背景也视为前景；偏暗样本会拒识。
- 颜色被二值化后，九几何负样本每形状的三色成为同一个轮廓。
- 全白与白卡无图案的物理存在无法区分；采样外细线依赖全ROI前景存在信号。
- unknown拒识只保证本组有限模型案例，不能推断任意未知物都拒识。
