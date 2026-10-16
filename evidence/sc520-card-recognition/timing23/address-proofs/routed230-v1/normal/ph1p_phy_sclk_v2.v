//------------------------------------------------------------------------------
//  Copyright (c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
//
//  Vendor      : Anlogic
//  Version     : 0.3
//  Description : Anlogic Functional Simulation Model for Physical IP
//                PH1P_PHY_SCLK
//  Filename    : ph1p_phy_sclk.v
//
////////////////////////////////////////////////////////////////////////////////
//
//  Revision    :
//  2024-09-12 - 0.3 - GS.JI - ce pullup to 1.
//  2024-03-08 - 0.2 - GS.JI - Add clk tag.
//  2023-08-07 - 0.1 - J.Huo - Initial version.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module PH1P_PHY_SCLK_V2
(
 ce ,
 clkin ,
 dlytrim ,
 clkout
);

 input ce ;
 input clkin ;                          // [tag:clk]
 input [1:0] dlytrim ;  
 output clkout;                         // [tag:clk]

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
MawFXeW6YbuSraS7cyw0rO/Yz2fnM0yLgUcdgtf47YVORis4mqtCllXtuEu7hnEh
6tqAbrp2qdmv3DSQ7BKpwdbbfHZXLS8yz5c8OYDWqKyism+T8XKVrLjqW1GexbYm
q5fVvNNoJfhX8AUhyjyDRJtcCLtrohogDz9bBDEBF/4=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
ncenrEgrM3Ljlo4N6AsDZnK+0z9L8ZbfZtv5MVfFCSr7p++j6yrBSkkvcvP4xAbc
qvjzvDyrNfxSi5rV8QLuEMC37XVZUtDPgO1raEgBLIzGPnS0aU21NKkuT3Iij7gY
7zQcKpbdz9qSnzakNb0nNeFyO2hZR+hcc+kCbnguEgk=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
E3zDSY1UA7sKapDs4hQ2Gp/L0MzTV/lrg5gFRvV84/2TDxLsy/PMR6O2efZCbQqw
YG4tJgkwZIeliw+wdwI24KA2kwcvznJto1Drt1tIzucHo9Oi75yUelMzRDyn7DXx
/RotcK3lJ7f/KV/cCNXQelEThMtlWEPsONbFs1nxxcW8fP59u3GJq48cPOPwgdPd
+V0ueMTyvAD0JzwYYMAc1QKabSoStjMm8cVuFGcMBE0tTcOTcMwwQ0V8RSrlgrC5
HRVb7gUUALMVYtAa4+P+u0sYGis2dqffkmU654c3NAZm4p8y+HyWV2nAKfXlp3FJ
jKu7jJVhxG/dFHttcp+nwg==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
aQ8/9IpSZoZzTBfIWbNBPiRKf1Z/qEHEJvskuQcOeUEyY8KiwCsF61/DHjFjbOzN
vFj0VQWmtlyoqYoQqk/N3pCKFb23O6oNE0VTx0jTljf113TYFSoiBSbKbIUcugdH
GRjL7qCUSAyV0eruq5/mNWdcKsKcpz2qSbM4wKnf4Gk=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
F7HVZPYZAgia6Umo8AV1iYYMcG7qnCXShb8RG802KAUvBguf12Ul9b1bsajcwNq9
F8ST8oeBhClTlhPbOtmadFZQfZI/OayZYRtKBRbldnx0/jyhlx/1vm3H8daitQQf
6JObrG8Mi3pRKCgFLFi0UaMyjgyOrDQfLyBtgI2DYIRNR9T+wJg7eN6d+6BRVCMW
9tcFoLsQioQfFfp/cKsUnWyNal/CnwrLYKNRrFsVdrG9XJ3aQ/0MdnQbqE/Bqc0n
/3c5/MxK5mUY7GpfqynXvJwrhHa6QQ9+8sIqi5kahpdlyM2c7FkQSnKGl4BiQEhA
5fQn6lH19WIoRAI+BwGCFg==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
p1B7Upzyll/NDLXwZpxSQN3umPFx4ju27E2IyWJskdor/sGXnvUT0JHEt+MpgvGj
EJUuNCN6L2HDTJh7mLhbMmseP4Z3mbUrG6+ybP+Gaqya6z71aYbMgMpblsXJ6Khk
khzrROrbQZztaq7ZP0uj+yuoyK9INwcW1WZsW25WbsaJMHXFdhZHxZp7Ejk1J37w
DjihSWtpwUrMG3c0FGJBt3AwmC0WZYmqq3bo7F0YYMhypZze+vOUoQ5VT3g4byMl
4hNT9EeiDmBQ1vHZ3WeSt6Q4cvUpOcYUlf+UGIb9HfiWst1uoggCYU/QuatomksH
lJotqdAmUYgl0WrDiO8mnw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 1008)
`pragma protect data_block
srOJTUiPGMFDb53MZW1U5dcIOnHBTR66WOhGKwSn3Tb4mwKERfsR62Xfy/mK0fDD
t0OW2MIJ0+/ek6ZE1yT3KG5awaADAO0P+wQ5y20silBLIzU9GXl85ZqGDZ5nzRpT
4IfpUwx3nkc1O9W10DQSLQ+U8edqOvRO5fpNiM6zQ2BXla6Fk56Yw1iqO23Vf2BM
x+p5vZ3A1bLQm6/d6dBEVxVALYPJMe33SbmHLRlpN27ZnMFLgMazgUcEQO9NiJzS
VToh4fjt0FL0j6hut8dPc3R7Lx6xcb2emwElyr8PDtTTBjUCPydGw6+T8JehrceU
8REfAvqQt0eGXn3rbwxUHCBEiKg8JNzFpQdQeP2cLFEnF+9vKflv/TgnTld1poq4
30/3yPWp6Rloyfr+uDxcH03NfGdGNQHzWBPLJIwfbHSlKO7UJa13z/Z6n9ylLJI4
cbcXc70Ya54P4/Vqm6ztvADR/tVDIz5k6eeuwW6R8sl6h6s7DFEWS5eA5IdjQSAq
FQqeL1lm5PtOYM6RlOQf1RjQhGt1YfX7HVNf3kfcfkEIqnfPTWlKZ1WL2jtXK1wK
umB+/FD6f5z+ij5DubiF3xIck0WJkdTs3d7ieBk6aZ8hVMA84ThxNNefTdQ7Hhe+
pGrk4+Rkzz3N/mQLo4vXP5NaJkrOkugBSIzpzWNWKJmSUSANsb9UQ0qh74usFxXB
JTHCmzIrL2HallAKHK1Du5O0wHoC/Z47fxD5XGiJlqH6MeYZMxpRGvcc25LajRwQ
lPkODATWrpKE3bLWL46E4W+7SofDyMZfHW7ulfQ2I1m0Mvq3shhS4gl+FPcML+kw
oAWv3kXUmSYxQdfOCvKI1Ck4P2j5JYN5xUf6oNatNJZzhixcRhsAVKK2pjF33Bch
tNzaMj2MaG744MWyRJunFB0n6nMYhqOU7Jb2s5FNhZEwj3+GM90QVL9zjLsqiT4C
vQduFdEG8kwhwX7U57USujiexTfMsb+BrqRAzaBR/24BjcceIyXNVR3CRsOBoXkq
0FZW6FWbxaxe9SRNwuaucNxxD56vZP39v7OkuXEg/87wgUB4wHokF7Die0Qyaow5
aeTmBaKFluribwt5sqeDeasNt8IdEbmMo/Ij1Il/Y5MO5KbNBhjPqeTvSzw0ZtsR
dNTYm4lMTX6nAzuupDuwpIbPCddInZEUiol6orppC78m/uWgHFimKl6noZHDVIME
+Yh7umndxbkqgWm7VXOt9YmhkPw8bp68nw+S1ZZKC4W+iFMzylwLXCYT0lC5Ht2V
2GhhVJYYFz21LFyHEtTk6fNyNWSQes/lgJKFq9wVAIb+gec4Xqn7w4Zx4Kr1Uwji
`pragma protect end_protected		
endmodule
