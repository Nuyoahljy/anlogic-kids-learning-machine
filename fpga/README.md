# FPGA 工程目录

- `vendor_labs/`：从官方工程复制并适配的自研基线，不修改原始外部资料。
- `custom_project/`：最终自研工程。
- `constraints/`：引脚、时序和物理约束。
- `sim/`：测试平台和仿真素材。
- `scripts/`：综合、仿真、清理和报告脚本。
- `release/`：经过验收的上板 bit、版本说明和校验值。

TD 中间目录和普通 `*.bit` 默认不进入 Git，只有 `fpga/release/*.bit` 可以显式加入。

