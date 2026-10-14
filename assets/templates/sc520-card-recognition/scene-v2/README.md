# Scene-v2 开发候选

来源是五张已哈希的打印图稿，不是相机照片。scene-v1原件保留；legacy-comparison.json回放旧模型并逐字段核对原记录。

320×180 bp输入，ROI为(40,30)起240×120，即可见960×480。采样(41+2x,31+2y)为120×60。边界每通道16档下中位数，档中心16b+8，L∞差≤48，四连通背景洪泛；原中心有效且3×3至少3点保留。存在门槛12点及至少3×3 bbox。边界相似点不足75%，或物体满足存在门槛且触边，保持present=1但卡片mask清零、积木重放白化；仍是健康未知。

20格位于32×32的6..25；side=max(inclusive width,height)，x=floor((20*(2*xmin+width-side)+(2*(gx-6)+1)*side)/40)，负数或bbox外为0。每类3模板取最小Hamming，再在不同类间计算second/margin。ROM1024行×15bit，bit=class*3+variant。

训练48/64/80/96 bp像素×4相位；选总距离最小，再两次选距已选集最远的训练项。评价51/59/67/75/83/91/99/103不参与模板选择；dense-sweep为开发期间48..107扫描，不是盲测。MAX40/MARGIN24数值保持，但有效面积从784降到400，允许错误比例提高，不能宣称和0109判别严格度相同。

真值先于模型赋予，失败原样保存。gain65为曝光压力观测，不纳入可识别契约，未改其类别真值。所有输入存PNG；rtl_default另存RGB/replay/mask文本。模型一致不等于识别正确。

system-cases.txt按绘图配方固定选择14类及空场/未知/边界代表，列为prefix truth_item truth_present；不依据模型结果筛选。旋转0/±5/±10/±15/90/180°及8%梯形是独立压力集，不承诺旋转透视鲁棒；两个不同苹果图是脚本另绘的负例，不是用户手机图。

局限：glyph仍为minRGB<180或色差≥40；纸白165时整张纸可能成为图案。复杂/低对比背景、旋转透视及相机成像未验证；同色物与背景或整ROI同色遮挡在单帧中不可观测。没有实物准确率或上板结论。

{
  "groups": {
    "empty": {
      "count": 7,
      "truth_satisfied": 7
    },
    "noise": {
      "count": 7,
      "truth_satisfied": 7
    },
    "shadow": {
      "count": 7,
      "truth_satisfied": 7
    },
    "card": {
      "count": 480,
      "truth_satisfied": 480
    },
    "card_perturbed": {
      "count": 15,
      "truth_satisfied": 15
    },
    "photometric_stress": {
      "count": 5,
      "truth_satisfied": 0
    },
    "edge": {
      "count": 24,
      "truth_satisfied": 24
    },
    "card_rotation_stress": {
      "count": 45,
      "truth_satisfied": 14
    },
    "card_perspective_stress": {
      "count": 10,
      "truth_satisfied": 9
    },
    "block": {
      "count": 81,
      "truth_satisfied": 81
    },
    "unknown": {
      "count": 27,
      "truth_satisfied": 27
    },
    "unknown_card_art": {
      "count": 2,
      "truth_satisfied": 2
    },
    "outside": {
      "count": 1,
      "truth_satisfied": 1
    },
    "background_unknown": {
      "count": 2,
      "truth_satisfied": 2
    }
  },
  "rtl_default_count": 72,
  "required_failures": 0,
  "legacy_card_pass": [
    27,
    135,
    135
  ],
  "dense_sweep": {
    "count": 1200,
    "passed": 1199,
    "worst_distance": 41,
    "minimum_margin": 57
  },
  "dense_sweep_failures": [
    {
      "item": 14,
      "size_bp": 57,
      "phase_x": 0,
      "phase_y": 1,
      "best": 41,
      "margin": 108,
      "predicted_item": 0,
      "truth_satisfied": false
    }
  ]
}

逐例结果及所有失败见fixtures.json和summary.json。
