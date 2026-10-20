# T029 RTL 放行补充

2026-10-20，Codex /root/shape27_delivery。主已读原implementation-contract.md（SHA256 68E643C29DBF37626CC6C3105EEABF0B5377F4312E6205ECB5CDF08E82C16900）和v4模型/独立证据，批准独立RTL与真实软件验证；尚未放行新TD/bitgen。

本轮新增恢复仅限圆。模型v4中可恢复canonical方/三角的分支不纳入RTL，另以model-contour29-final.py收窄并保持原模型字节。原full glyph严格圆/方/三角、原主色2/3与各2倍保持；新body其他几何只参与冲突/拒识，不能隐式恢复方三角。radius19明确为新增采样别名，非“旧shape20完全未变”。

v4的148合成有46个原定圆输出未知，独立新增gray25圆full/body同bbox但外残差18也输出未知，保留Truth1。原T027固定62必须保持，正常radius100/plain七角度须恢复；不宣称全部损伤、阴影或现场圆成功。外appendage证据不清时宁可未知，不把其改成无目标或改标签。

模型与实现都要求恢复圆通过body/seed近方、极值边界无修补、body圆alias<=20且严格优于非圆椭圆、full非圆椭圆>20、full glyph外残差<12、原full颜色覆盖及同body赢家，最后再与cardbest差16比较。原基类和恢复基类都在最终match_event资格后进入三帧；negative_only永不成为SH公开位。

实际full颜色核沿原MIN_AREA=16；scene/body的最小有意义成分为12。原合同“均至少12”只是必要下界，模型早期用12但固定样本皆更大，不作为RTL放宽full16的依据。最终恢复必须原raw_valid成立，不能绕过full16或2/3。

D0290诊断D仍为full glyph的三个原几何距离，SH可包含新增body恢复圆资格。因此D圆>20而SH1/RB1可以合法，需结合内部body_axis/negative/recovery证据理解；公开800位包不扩宽，SH仍只编码圆/方/三角，ellipse负类不泄漏。
