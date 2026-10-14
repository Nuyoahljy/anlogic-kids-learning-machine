//------------------------------------------------------------------------------
//  Copyright (c) 2011-2025 Anlogic, Inc.
//  All Right Reserved.
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
//
//  Vendor      : Anlogic
//  Version     : 0.5
//  Description : Anlogic Functional Simulation Model for Physical IP
//                PH1P_PHY_GCLK
//  Filename    : ph1p_phy_gclk.v
//
////////////////////////////////////////////////////////////////////////////////
//
//  Revision    :
//  2025-03-11 - 0.5 - GS.JI   - fix AL9100-2429.
//  2024-12-16 - 0.4 - ZX.Hao  - sync with 9000 ,RAV-9982
//  2024-09-26 - 0.31- GS.JI   - Fix modelsim eror RAV-9476.
//  2024-09-10 - 0.3 - YF.Meng - sync with 9000 , al611-1340
//  2024-03-08 - 0.2 - GS.JI   - Add tag template.
//  2022-08-30 - 0.1 - Y.WANG  - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module PH1P_PHY_GCLK(
 seln,
 cen,
 drct,
 clkin,
 clkout
 );
 input [1:0] seln , cen , drct , clkin;
 output clkout;
 parameter PRESELECT = "CLK0";       // "CLK0", "CLK1".     [Template:Initial clock output selection.]
 parameter HOLD = "YES";	         // "YES", "NO".        [Template:Output hold setting.]
 parameter SEL_TRIGGER = "POS";      // "POS", "NEG.        [Template:Sampling edge selection.]
 parameter GSR = "ENABLE";           // "ENABLE", "DISABLE".[Template:Global reset enable.]

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
bb4jhMcAqoeT3ietOKbdsD/0sX+28Ft/WwWVOj039oTnGHzbD/RhYeHEQe38N7+6
95vmyzDqOe5fO5nofT6IkhIM/zdIhSSqcomEek1fQm4KmoZZTq5DKNDTGg2yUsxE
vadbrMxjzy9FG+6A7EAvpgZqr8BJDh4l1Pu7cHHBo24=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
Ee3Gq+3HBc8mHNsW1bu6ykIl74a9SV0cs8KbtkyYHoYxvgpa4XzzbVzabf+ik8bc
KolAEI1Vqcp3VoGe47NplucIuSLS++e/MbVOjU8CdIcOmSU7gZQAFKAjoXivdb2p
k9328NzRU6UbdzCVXMuZjQFXuZ8x/EdqSwo35Lt1YeY=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
gLxwrX+3upU+E4iWRrDZ9EctlkIvBxwbzihecx4J/ic1htxZ7l9SQRoY4AwLkdqb
qerMrZ2iuTo/hm4UWOur4aHfCKhnoYzqke922nmq2+7y71B7TGxWXZ6fHT40+AAD
FKm1RnbSkQZvIlgF0CoyFBXBUn6OyXzsKmw740vDBTVAvBEy8rZIs831HNRMOtDd
j//6xYi2Y741vb66M4KqjiLvLmyrbK3WEZ1Yon1YN6aJ7C894H0Zeuz+rrWwQ6l8
Ld1WoVSuHKmVmiJw2nF8T/fawutKamNbyQ5z5AUoCJKNnq5lEcuUyE6XTD2quDbV
3tZgdsW/BDJ7aNcco1VUjQ==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
CUEGin2NSZy8cFXWAodKFv1TteBboO+FOVjH4SzwLcPV0DNX1sybnYl3804Ir710
sHG92fL3Va6Q8Sn1+Orm7Lt8py5clcf97NSM+k2Eu25OMJXEk2bhr9yGAaBbpxKP
obAxAupeNMpoTb+bo+ccjfZhFxB8Qz0NYGAzznd/GUY=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
cY3Y3B/V3KeX9O+pi5vQOa7baUICwvFBUk89EkfoLZwJAWPBRpxOqXUXtllYfsF5
MwBCR19/dIdBuLkXWb4C7mnaPIqtZRtZ2ItAYGHSyLpDdNILRj3f4drG4nY3yKqN
3YDFqRPzOhNyYuROC/kq2CjCwR8E2MaK6SqdX6MY2L9+uaB6jpLPvOQWg9rawTaX
VScUrWPX1CbWesGsm8e66YlIXKQORV/isK/0MY97P8Mjuuo9eKH4LVmlKOwoxRT2
LLeS/T4rG0HfVo2lUeA/sMHPwtBWN7qYkB9pJf6vrJOoQ+M++p6a6FiRmOHwfw1J
TuE0q2WTUzzJpn1CYDvtGQ==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Hhkw78Irl44euzJesAHfFwuzVEPWTHpDJb5FINfaOG8kA+P7kKHFpggtVnZQiMeA
hP5yz3TRzfzCLqHjX56n6Kn6GofvUsKGj398c43ZnDPIeFoCGy8+6mmh/e5fS1yp
mXALFF8vRUmJ6h/VtzzW5as3IbbZBSSnh7QKz2DHD+ZfFMmX6F/yc6+90+XutFsi
a6SXvPV80WRyGOUnOtbY/l74OsUWkfjzdwB3ZXJv7NbckELhjLY4Yoh9OeY9ImfX
EE6V1gjT7rnfb537k46LImE2ySCu3kQvAHNyrKQ2TZrqTAAPZfytKIifAFbz6jti
4X/ww0xthOCCQcC+yX61Iw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 1072)
`pragma protect data_block
gYyxceEE7N5lEpWwT6T1n8w5E1ISoWsZomrSd3EeajIXyzkUJn4Xk7ufqIYeAbNV
Zg4KMKAI0uaJdk9Hji9UiR7d/jdrL7NRSFdA08g6cin6fI9O8pt3zdZJfy0RbEMJ
F8a7+UdNwSOeyiAsInnmM7+vbAoLTm534kL9AtU11FtkhatAIjk5f9vT9bknM/rT
5hHHUxLEzAWFV+6aWjlbwzulbPLrQIgYkl4nTVWeuF8H6v7kfbOX4XhMIpxZQ8nv
t3bLY7GScIbKYFmTAt2gP1UIDdS4Ah4bk/C+u4ihFGAecWxHJSZgTt/Gd+51k8gK
nsudAfwGOOZc1+W+dOveWX5eZ02q1/ha50lo2hZXtmL94RYZ/53v7BeK2WoZ7/iZ
iMeS1nKAfV4nKunydj/uD2V7kpIsKzlkxLv80v+hPorjEpxgQPCbdO0VveP2tSVl
ePWi92oA+QW9Z1ogH11oZ2gRDi1SeI6dgxxo/y2iwnts3jQFe1/QoJ6iBiH0LM7V
9JNrX8EHehGipxtN8mHl1CaV3WMx6+Y22iUAnwlfYVHYpcOJvMA5qwrHFX/OL1yL
g+4aO5BaQexX+8Jp/tUlKh0CzEYd2ml/EgerSdtboguAgn99zbnHl5Q+JCN1cXAX
7UwTV6jfDSNQBTga7ySoiOWIdsbY8YGiCTl7avLdswqyj2z6CW049Y4Oj/8a153c
QAhZGqSUL3+FDsCX1hbp4mlcFo7EfsZyGXfRqf5QYWcboosUNmJ0qRCyTsBp877/
z/YdVKpv+BNsQ8sZIr1nu8LIdzIb7+iKCXHA0QHvf6OF1EFmqvD36RsKabpJx8eF
OagBTMe6KwabpsmXlxvfCfdXImh5zHDmrcpg00cyvWGMTRhidXrWqhmfEqDCS0cD
GiYGRxalBKa6Gx2z3rBkmi6lFqx60UgKjNJGEi0aSGY2hLwqAODNcMGYdH7BGjTP
RONvCmkHKAtpg97cWHie9L/bX5PNryOzkHRl6lbV2zVJmFzXgm8ltHyETodX/tK0
2ZO/EIkJbzIUNtbM7iIae7f98Idkv1Fo3p7RHhTu04VOlZ8GOWfLqWoFzyrwBFJd
DcQIF/Zy6N6NvNt1lr2LykP4KG44wJvQNyMDDbNiEn4kNB6Lb2W6dP6n4BHo3MQc
S86R945LV2nOvcop4yyVD12tESaPP82O6iBYT7uWbaQ6lm0221ZDYWshmR54460T
gn7/dm6opYvgq8YMtu1+GzrVKbwi2QoB1e62eShvzFlChV9/7a3JmhoFRi0/gcNm
Iw53EiDzWYeZAPyG2BqSuarx4fw1l1XlbRaomjCBoSCzzxSTPssCs4o6/I3Tw9tG
Qk1tITsB/NdTNQMpnUZDybv6pMDdAOPbM6n+Y/f7A7T9+TMlvmqzG9WFa5HaikFx
g1v8jKWQVIYuLjpaoGw4ng==
`pragma protect end_protected	
endmodule


`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
zf2Cjl9ct2rD0KEZhSogWpK+GI5x7a29OBuOUxrlOYoNqa8tpw+jaRR95yzgfRf5
RwHKO1G7BZqU7sRRtP1QWAJpHuyBsRnEw4nFWmOoiebYbvVg8/bR9UtFlrUhQ8Zr
GUWnk2kxeGIec2LVTZ/z34lzTUSUcwrcYrz32w1mO3k=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
Go13FK8KQ9724MAM8AsUvqwOtR7drXpFZRDCHunD3AtHzu4ifrYtcmDnAvx0QW3o
mwxwhdGmtzWzhqFwRN4F9hDUMsc5D0qjI6qgewdHCdKjLozeSM1l9TO4CRZYfA4e
ghkiNaMGRlTn3W4iwlk7So7i6CijszCIKf0fVFHgTdc=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
hbXKn08MjQnPJdXck1Z+MYv+4sw4R0vkBemV/chZTZ0P7yzEhxCFlvAQPkYld6dm
8+ImCAVzeMvg0LV9ANa194gLBTIdDsJhIP0XwRlnD7ATiz/GN4wL1Zpbklo8Z9g/
hDqvCNmmrraAA9D9kOuUnHmRX2jIHZNyCvDkFIhfTY/ajCZKSaWPKZO8ZdJcJYpa
ATIz6ir7ecAEh1s3xEsIdXRt2rmoHGfwOXUr2qnRxBH+0WR3tft0n/haiG91XVaG
gwEJuxvcvzbyufET4lMcTGZG4hN+j5j9Bg+i9wpO/kQ2Q82TlY+3vSTmDHG7JQDs
fFk1gWNOnmd2rt3Kg40/5Q==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
NR805lZ6O9spZNi+gc80itSOTpuofEiiooSG3r2neJ+XQ1FfhTM0WTyXGgb8sEQZ
VDl0EIHbNPnS6QzNLditPw8LtMAuIlEyl1u1zKl0kCzM6AqupO7u+FlhBiK09j1w
IOQPGHhVpvezVY7dkZxEFkx+xdGC5rIoQWhwgA6BN68=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
as9aZsaaC5U+hZrGjmrMveplQZqLhkYoCsBituA5zmC2MUmIKPH2SYlo4+qMw7Qs
JJFBNH9p8ZPNAuys04woqfeuxSA0YODKo+x3FByEZmjlgLUDUcsR50Rm7T/f9fRO
Y/Foc/f2Fukr+On4zNQY4z56IM6Xaj2oVJ7mDAygjsWKX+SjrWZqs7DdocBfWj/q
RKgPK0IAH/2TmVGTwbc164guwQN0gao21RWy7HKbP5DxPC7EKgJ7QuHYL5/F0C8j
EvQmEkMs4ueKy8USsYl/3mrwM6gB9Dzq815RRcxwAerK02LvTvCnn4sCXDajoyHv
Gs1p7u9MGLjOI4hrrycQMQ==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
J8J4F6RKx7DoZfrTzV3e0v2HPQQm3ExSbWEnGIizqLE7yNoIsoSiej4Nh0pNY1S4
52BDyUCGY6f0abrWlefGtz4spEhAkC/eKvvnaxAVd8ME007LQpgTcB3DICpfPXYq
SsQS22470tgzlWVdgGCO62yy0KFLzYp+5gYo4M6tgiIUTk18bIFXmQHIr1TPQiQi
O5GVnUX3tqzJFZAocIGGbKy3jjnttcTY79ILH0MiRlu5PWkjM2IJ+FN1KPIPwdhG
+fysqe2AVPoyyTMlCROysE58TOD2e+otxxzNnkp7GOsSOtBt7oXowSUnhlGSi3Df
7rxoVi1+TKLQUBZ3RBRByg==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 3248)
`pragma protect data_block
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
`pragma protect end_protected
