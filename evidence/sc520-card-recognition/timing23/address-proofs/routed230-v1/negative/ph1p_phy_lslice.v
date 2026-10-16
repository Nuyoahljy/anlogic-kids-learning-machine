//------------------------------------------------------------------------------
//  Copyright (c) 2011-2023 Anlogic, Inc.
//  All Right Reserved.
//------------------------------------------------------------------------------

////////////////////////////////////////////////////////////////////////////////
//
//  Vendor      : Anlogic
//  Version     : 0.3
//  Description : Anlogic Functional Simulation Model for Physical IP
//                PH1P_PHY_LSLICE
//  Filename    : ph1p_phy_lslice.v
//
////////////////////////////////////////////////////////////////////////////////
//
//  Revision    :
//  2022-10-26 - 0.1 - GS.JI  - Initial version.
//  2023-09-20 - 0.2 - Yuan.Wang - change OFB setting line:130,678
//  2024-06-27 - 0.3 - LB.LIU - BCC&SIM check, move LUT8MODE from F78MUX to SLICE
//  2024-08-01 - 0.4 - weiheng.dai add input delay for dram_di in
//  anlogic_lut5,jira-RAV9099
//  2024-08-05 - 0.5 - weiheng.dai add o_lut5a o_lut5b gating for lslice,
//  2024-10-30 - 0.5 - change ce_gate logic at line 713
///////////////////////////////////////////////////////////////////////////////

`timescale 1ps / 1ps

module PH1P_PHY_LSLICE  (
ia,
ib,
ic,
id,
ie,
imf,
ima,
imb,
cea,
ceb,
clk,
ssr,
asr,
oqa,
oqb,
ofa,
ofb,
// cascade signals
imc,
fci,
fci_f,
fco,
fco_f,
shiqa,
shiqb,
shoqa,
shoqb,
ft_lut5a,
olut5a,
relut6,
f78i,
//func8_sel,1210
//func8_olut6 1210
//following control signal comes from hardcons
dffshiften, // dff shifter enable
dpram_width,
dpram_rammode,
dpram_shiftmode,
dpram_we,
dpram_waddr,
dpram_byteaddr,
dpram_wclk
);
input  ia;              // DEFAULT := '1'
input  ib;              // DEFAULT := '1'
input  ic;              // DEFAULT := '1'
input  id;              // DEFAULT := '1'
input  ie;              // DEFAULT := '1'
input  ima;             // DEFAULT := '1'
input  imb;             // DEFAULT := '1'
input  imf;             // DEFAULT := '1' 
input  clk;             // DEFAULT := '0'
input  cea;             // DEFAULT := '0'
input  ceb;             // DEFAULT := '0'
input  ssr;             // DEFAULT := '1'
input  asr;             // DEFAULT := '1'
output  ofa,ofb,oqa,oqb;  
// hard connection list
input f78i;
input imc;
input ft_lut5a;
input fci;              // DEFAULT := '0'
input fci_f;            // DEFAULT := '0'
input dffshiften;       // DEFAULT := '0'
input shiqa;            // DEFAULT := '1'
input shiqb;            // DEFAULT := '1'
output fco;
output fco_f;
output olut5a;
output relut6;
output shoqa;
output shoqb;
// MFU dpram hardcon special input
input dpram_rammode;        // DEFAULT := '0'
input dpram_shiftmode;      // DEFAULT := '0'
input dpram_width;          // DEFAULT := '0'
input dpram_we;             // DEFAULT := '0'
input [4:0] dpram_waddr;    // DEFAULT := "11111"
input dpram_byteaddr;       // DEFAULT := '1'
input dpram_wclk;           // DEFAULT := '0'

tri0 dffshiften;
tri0 dpram_rammode,dpram_shiftmode,dpram_width;
tri0 dpram_wclk;
tri0 dpram_we;
tri1 ia,ib,ic,id,ie,imf,ima,imb;
tri0 clk;
tri0 cea,ceb;
tri1 ssr;
tri1 asr;
tri0 fci;
tri0 fci_f;
tri1 imc;
wire rsb_ci=imc;
tri1 shiqa,shiqb;
tri1 f78i;
// Logic parameter
parameter MC1_ENADDER = 1'b0;
parameter INIT_LUT5A = 32'h0000_0000;
parameter INIT_LUT5B = 32'h0000_0000;
parameter LUTMODE = "DLUT5" ;               // ""LUT6","DLUT5"
parameter LUT5A_SD0 = "IC";                 // "IC", "IMA"
parameter LUT5A_SD1 = "IE";                 // "IE", "IMF", "FT_LUT5A"
parameter LUT5B_SD2 = "ID";                 // "ID", "IMB"
// Output MUX
parameter OFA_SD = "QB" ;                   // "QB", "LUT6", "LUT5A", "F7CY" 
parameter OFB_SD = "LUTX" ;                    // "LUTX", "SUM", "QA"
parameter OQAMUX = "RELUT6" ;               // "RELUT6", "QA" 
parameter OQBMUX = "RELUT6" ;               // "RELUT6", "QB"
// ADDER related param
parameter ADDERMUX = "0" ;                  // "0", "IMB", "LUT5A", "FT_LUT5A"
parameter LOC_F7CY = "CY";                  // "CY", "F7"
parameter CIMUX="FIXED";                    // "FIXED", "MUX"
parameter DELAY_EN = "DISABLE" ;            // "DISABLE", "ENABLE"
// Register parameter
parameter GSR = "ENABLE" ;                  // "ENABLE", "DISABLE"
parameter CEAMUX = "0" ;                    // "0", "1", "SIG"
parameter CEBMUX = "0" ;                    // "0", "1", "SIG"
parameter SSRMUX = "1" ;                    // "0", "1", "INV"
parameter ASRMUX = "1" ;                    // "0", "1", "INV"
parameter CLKMUX = "0" ;                    // "0", "1", "INV"
parameter REGA_SD = "OFA" ;                 // "IMA", "OFA", "LUT5A"  
parameter REGB_SD = "SUM" ;                 // "IMB", "LUT6", "SUM"

parameter REGA_REGSET_ASYNC = "SET";        // "SET", "RESET"
parameter REGB_REGSET_ASYNC = "SET";        // "SET", "RESET"
parameter REGA_REGSET_SYNC = "RESET";       // "RESET", "SET"
parameter REGB_REGSET_SYNC = "RESET";       // "RESET", "SET" 
parameter SSROVERCE = "DISABLE";            // "DISABLE", "ENABLE"
parameter LATCHMODE ="DFF";                 // "DFF", "LATCH"
// PMU local global control signs
parameter TESTMODE = "OFF" ;                // "OFF", "ON"
parameter DISRAM = "DISABLE" ;              // "DISABLE", "ENABLE"
parameter RAMMODE = "SHIFTER" ;             // "SHIFTER", "DPRAM"
parameter DISREADBACK = "DISREADBACK" ;     // "READBACK", "DISREADBACK"
parameter FCIMUX = "0" ;                    // "0", "1", "FCI", "RSB_CI"
parameter LUT8MODE="OFF" ;                  //OFF,LUT8_ON
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
szdcpDO37QPkIsgHF/4hqmFYSSay0/m0RXbHfz2JK9bOvoU/12ncw0ZReyJVQ7gT
Tcdw46poBhaUqeXr5gjdl6wgmvvYp2MJ02m3hACUprxtxwqz+2bsCH68sRgB+tjH
F3rOeBwjfyvSyv1NuQh6C6iPRcovKdbYip7q6qQvZew=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
DNOHW2iV7b1UKiZODXLRcCceIIYfYQFzk8fVB/SAaVkov0TCMVEvAHBX+sQMEYQl
iGt56DL6qXfy7vRPdOBwElx7n81uPXybOTUMtK9V2oR6wxZzyE1i2zGceRqf0fjF
xfE+K5OfxQlVqBFpJ+WR7vZegl9qM4nbatL+YoS4lg4=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
GujBv+PDFVjHx08XI0K3KaAWDF9P6lMF5Frb2bsZv25FukyPF+cAiDazYN7lyGYh
kLTLHRgVJEWo6EuKvI70aDes7WZPwBMe0qkZwORokDJ3JyZTBJR48TPjQOnRrrkj
OT1qQxk1qCGdSWEiOxffecBQSBjEJMjljcTJB+IqOis0MKvW2YIThjQ0LivyAhNy
940InNIfpi8DKJVliI4NGmww7BBPmJOq/WmNih3P5hIr3ArvCjMvkT9UNEip4sQs
vyIx1EKjDb5UEhZKWqRob70vZanTMxJHxXPnfzGOOPWJ96P9rcuV/41EOYcb3K6j
H4lCAPlWRII29E2GrkMDOw==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
E6qLbvcn3hUpL8qsKUSx0RX9H2Y8wHRJ1uaQPrhrwmdJ8e1dXT5QQGaejHQhq/KF
ODPBhIrP4y4dw6oKa/njaJgxmdwVgBgYtWbZ2ouTj64wW5DdDKFndwxtwJoiJJML
ZtNtOaXQ3w07NKCkOjbxbi3cucm9p+dG5UJ/Df7ZPtE=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
Lk2i6SuH0JZFSPKsiT/nHV1sXIP8Dupnkldfr8wmvoUqgdtTDuixKyejszoQPspm
SDLS1z0aj9l7IZWb3Or/sMgY1Nhd9WZIer4+xYvM9UWEIXXaZfX98BD/+Ox0gGoK
dUNZUilNJacnobu0WWeh3mSz0j2j9PDhlt0YU16vdUgNZlrfS9OW7SeE9+DJGEZ8
h6hueWh/0hkHAXXCz8Kv6gRq3qV0ieG0YO1l3367073/xpSHP5RACjMj1Qok9048
zgZB8Tv29PIr94AbTzThsrNoH5VTbiYeSAyoL75EX5Rv3jrIZNERSUCQt4C3Mxet
RLf/JCl16w7p6i5Tj5Qx6w==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
zxw74GXyRBK5aFboOKPVQNWixYLDr31CkRegW1z76mrl8XAmdORkg2lVkTbF47tn
ej3hw3Z8PURN01iTUoItNwRK36NYOAo3iG2p/H1GNZGW1mqysC0/SBCPPVHsT5El
AgRaUtQlLKFZBfk1bOvJ6DZap3kZAph+krV/b4GDuCjSFGcBf9cXASh7svve1dtr
QZamydSnJvS+awlN2jhOprY1esslkc4tqRdkwFkwFgAs48hRjO+xasNmfex9w1P0
UPJ1VVrkTb3rh+IHQ9uTlRZvJ/ztEN2//6g/0rZS0gDEYmmZBOryDgn3mHHWhmHu
tvJwPqtXkHHD+FqRG3hq2w==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 16272)
`pragma protect data_block
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
`pragma protect end_protected
specify
  (clk  => oqa) = (0:0:0, 0:0:0);
  (clk  => oqb) = (0:0:0, 0:0:0);  
  (clk  => ofa) = (0:0:0, 0:0:0);
  (clk  => ofb) = (0:0:0, 0:0:0);  
  (dpram_wclk  => oqa) = (0:0:0, 0:0:0);
  (dpram_wclk  => oqb) = (0:0:0, 0:0:0);
  (dpram_wclk  => ofa) = (0:0:0, 0:0:0);
  (dpram_wclk  => ofb) = (0:0:0, 0:0:0);
  (ia => ofa) = (0:0:0, 0:0:0);              
  (ib => ofa) = (0:0:0, 0:0:0);              
  (ic => ofa) = (0:0:0, 0:0:0);              
  (id => ofa) = (0:0:0, 0:0:0);
  (ie => ofa) = (0:0:0, 0:0:0);
  (imf => ofa) = (0:0:0, 0:0:0);
  (ima => ofa) = (0:0:0, 0:0:0);
  (imb => ofa) = (0:0:0, 0:0:0);
  (imc => ofa) = (0:0:0, 0:0:0);
  (f78i => ofa) = (0:0:0, 0:0:0);
  (fci => ofa) = (0:0:0, 0:0:0);
  (fci_f => ofa) = (0:0:0, 0:0:0);
  (ia => ofb) = (0:0:0, 0:0:0);              
  (ib => ofb) = (0:0:0, 0:0:0);              
  (ic => ofb) = (0:0:0, 0:0:0);              
  (id => ofb) = (0:0:0, 0:0:0);
  (ie => ofb) = (0:0:0, 0:0:0);
  (imf => ofb) = (0:0:0, 0:0:0);
  (ima => ofb) = (0:0:0, 0:0:0);
  (imb => ofb) = (0:0:0, 0:0:0);
  (imc => ofb) = (0:0:0, 0:0:0);
  (f78i => ofb) = (0:0:0, 0:0:0);
  (fci => ofb) = (0:0:0, 0:0:0);
  (fci_f => ofb) = (0:0:0, 0:0:0);
  (ia => oqa) = (0:0:0, 0:0:0);              
  (ib => oqa) = (0:0:0, 0:0:0);              
  (ic => oqa) = (0:0:0, 0:0:0);              
  (id => oqa) = (0:0:0, 0:0:0);
  (ie => oqa) = (0:0:0, 0:0:0);
  (imf => oqa) = (0:0:0, 0:0:0);
  (ima => oqa) = (0:0:0, 0:0:0);
  (imb => oqa) = (0:0:0, 0:0:0);
  (imc => oqa) = (0:0:0, 0:0:0);
  (fci => oqa) = (0:0:0, 0:0:0);
  (fci_f => oqa) = (0:0:0, 0:0:0);
  (ia => oqb) = (0:0:0, 0:0:0);              
  (ib => oqb) = (0:0:0, 0:0:0);              
  (ic => oqb) = (0:0:0, 0:0:0);              
  (id => oqb) = (0:0:0, 0:0:0);
  (ie => oqb) = (0:0:0, 0:0:0);
  (imf => oqb) = (0:0:0, 0:0:0);
  (ima => oqb) = (0:0:0, 0:0:0);
  (imb => oqb) = (0:0:0, 0:0:0);
  (imc=> oqb) = (0:0:0, 0:0:0);
  (fci=> oqb) = (0:0:0, 0:0:0);
  (fci_f=> oqb) = (0:0:0, 0:0:0);
  (ia => fco) = (0:0:0, 0:0:0);              
  (ib => fco) = (0:0:0, 0:0:0);              
  (ic => fco) = (0:0:0, 0:0:0);              
  (id => fco) = (0:0:0, 0:0:0);
  (ie => fco) = (0:0:0, 0:0:0);
  (imf => fco) = (0:0:0, 0:0:0);
  (ima => fco) = (0:0:0, 0:0:0);
  (imb => fco) = (0:0:0, 0:0:0);
  (imc => fco) = (0:0:0, 0:0:0);
  (fci => fco) = (0:0:0, 0:0:0);
  (fci_f => fco) = (0:0:0, 0:0:0);
  (ia => fco_f) = (0:0:0, 0:0:0);              
  (ib => fco_f) = (0:0:0, 0:0:0);              
  (ic => fco_f) = (0:0:0, 0:0:0);              
  (id => fco_f) = (0:0:0, 0:0:0);
  (ie => fco_f) = (0:0:0, 0:0:0);
  (imf => fco_f) = (0:0:0, 0:0:0);
  (ima => fco_f) = (0:0:0, 0:0:0);
  (imb => fco_f) = (0:0:0, 0:0:0);
  (imc => fco_f) = (0:0:0, 0:0:0);
  (fci => fco_f) = (0:0:0, 0:0:0);
  (fci_f => fco_f) = (0:0:0, 0:0:0);
  (ia => olut5a) = (0:0:0, 0:0:0);              
  (ib => olut5a) = (0:0:0, 0:0:0);              
  (ic => olut5a) = (0:0:0, 0:0:0);              
  (id => olut5a) = (0:0:0, 0:0:0);
  (ie => olut5a) = (0:0:0, 0:0:0);
  (imf => olut5a) = (0:0:0, 0:0:0);
  (ima => olut5a) = (0:0:0, 0:0:0);
  (imb => olut5a) = (0:0:0, 0:0:0);
  (imc => olut5a) = (0:0:0, 0:0:0);
  (ft_lut5a => olut5a) = (0:0:0, 0:0:0);
  (ft_lut5a => ofa) = (0:0:0, 0:0:0);

// 2020/11/03 add
  (ia => relut6) = (0:0:0, 0:0:0);              
  (ib => relut6) = (0:0:0, 0:0:0);              
  (ic => relut6) = (0:0:0, 0:0:0);              
  (id => relut6) = (0:0:0, 0:0:0);
  (ie => relut6) = (0:0:0, 0:0:0);
  (imf => relut6) = (0:0:0, 0:0:0);
  (ima => relut6) = (0:0:0, 0:0:0);
  (imb => relut6) = (0:0:0, 0:0:0);
  (imc => relut6) = (0:0:0, 0:0:0);
  (fci => relut6) = (0:0:0, 0:0:0);
  (fci_f => relut6) = (0:0:0, 0:0:0);


//setuphold	
  $recovery (asr, posedge clk &&& (done_buf!=0) , 0:0:0 );
  $removal  (asr, posedge clk &&& (done_buf!=0) , 0:0:0 );
  $recovery (asr, negedge clk &&& (done_buf!=0) , 0:0:0 );
  $removal  (asr, negedge clk &&& (done_buf!=0) , 0:0:0 );
//posedge		
  $setuphold (posedge clk, posedge cea &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge cea &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge ceb &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge ceb &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge ssr  &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge ssr  &&& (done_buf!=0), 0:0:0, 0:0:0);	
  
  $setuphold (posedge clk, posedge imc    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge f78i   &&& (cea_tmp!=0)  , 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge fci    &&& (cea_tmp!=0)  , 0:0:0, 0:0:0);		
  $setuphold (posedge clk, posedge fci_f  &&& (cea_tmp!=0)  , 0:0:0, 0:0:0);		
  $setuphold (posedge clk, posedge ia     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, posedge ib     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, posedge ic     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge id     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, posedge ie     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge imf    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, posedge ima    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, posedge imb    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  
  $setuphold (negedge clk, posedge imc    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge f78i   &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge fci    &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (negedge clk, posedge fci_f  &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (negedge clk, posedge ia     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, posedge ib     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, posedge ic     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge id     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, posedge ie     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge imf    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, posedge ima    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
//negedge	
  $setuphold (posedge clk, negedge cea &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge cea &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge ceb &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge ceb &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge ssr  &&& (done_buf!=0), 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge ssr  &&& (done_buf!=0), 0:0:0, 0:0:0);	
  
  $setuphold (posedge clk, negedge imc    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge f78i   &&& (cea_tmp!=0)   , 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge fci    &&& (cea_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (posedge clk, negedge fci_f  &&& (cea_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (posedge clk, negedge ia     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, negedge ib     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, negedge ic     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge id     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, negedge ie     &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge imf    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (posedge clk, negedge ima    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (posedge clk, negedge imb    &&& (cea_tmp!=0)	, 0:0:0, 0:0:0);	
  
  $setuphold (negedge clk, negedge imc    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge f78i   &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge fci    &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (negedge clk, negedge fci_f  &&& (ceb_tmp!=0)   , 0:0:0, 0:0:0);		
  $setuphold (negedge clk, negedge ia     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, negedge ib     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, negedge ic     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge id     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, negedge ie     &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge imf    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);
  $setuphold (negedge clk, negedge ima    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
  $setuphold (negedge clk, negedge imb    &&& (ceb_tmp!=0)	, 0:0:0, 0:0:0);	
endspecify


endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
SBeP50zmx8ma4G4A4uTIWnhNO/yPUC7F7MlkRkxbeRgWJjsD3C0xmqpmTO2NgaxP
oBR4MNJbtf+Jkd+7tqQZjwXxQrXT/voE40TjT0JbU/fsEX0q98IAAWhJIFpMYbKA
PznF9BNBIS+/m8+w1LWTNu8uTKV6PkZOmV4GrZNk5+Y=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
SE7T713iyFx59j2Nyc05lOhcZtxmQgsMC3VJ4Wm5THvQl7FrWagmFZufjg8KNa2w
3bZiXcewERFfOptn+3tegAJbot5qoveJoNzVETJYnFk7IHlOG+oCGViAMN2ugI3w
FvYcdXmeqL4a6VkmIZD26YP7lGmC3VVxq5Iqz85sK4c=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
X6CjasMVsSKghysMBSo84qfV8c3t61G5aa8srEwtt1HwTSx0NGj+Sx4iyW8zR/Sa
Cc5J9wAZJDl6Ii9DAzkXc/Giz8NzU2dImwbplfsLoYrXuHGTFQD6LWgxhunTDZQ1
0dBetfnUKaUpzBVFdAZx4SdBnqxJ2KNul2dTnhPe+EgfHJ3DYzgPjglAxmLuH/dq
Izn3+t/6zL2GNMwg67VN2KaT1EXib/KqBM/mJBoDnkQD64r2d/BtLd3rZf8AOTVt
VRj1hUlyWntja3BF/3+FH2kZo8ajR9wbQnjHHVLYloQm8WakNutPCMmHacuMh7ai
m1mxiTHWjjWLobUC2Su2OQ==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
ZuxKTTj+aptNtTGWav8/L74ONcHQNd9wLhIvdwjgA2Xs+YcMtvD/cIGJojzWp0lP
CQu7e0Gicjy9p57mNwFLIwfyolAS/TgQ+Bkt38CDeW7Y+QOwKUWfACBGbAPGXORw
SJivpEAozpkfx/4KQ+8L146mfV6o4pd201mcbatcKx8=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
WVtXBkujJEgywghs1v9xXUcl0u+hItITRmlCtiZRSIo4EdFd2sQODimCCcZf7drG
VOk5xeYJRa6Gs17mrv3lCCXYzZbieunyunjIBmwV41y8n0C6rPtyX1s0KHnurF6q
DN8hc851XVwO4cy4o6xKeOAH4LoZ1CQU0wDWOT4MPYk0pJD2JFDJSgnc3LJolbwv
TZ1BshzRMMdW4BU4N9IWlN0mqaP7QyE9uN4/9o5E3n5pefqDUjU8xStWt27CyCSB
pQjBpi15zi1HofgDBnpmISu0TgLxbxxBLKugmOwxUGGv3qL7EjDOlNQ7nmZ/JaQT
IgTKb3y9RqpipEi6A7R7aQ==
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
hcSsgUxmtExgj+ZHTvz/y9BAGVrBzBzkZUQvc4Dw1916QSIHk/po/wNFUY718Si0
deRkA9t3KrVVvzLua918iIp7g2iomrVbX97lIs0zfPz6QpkAa5g87wCat5hp4hmd
mNOHQPB/94tjhWdhuehq8e0uOeD4V/oflqAnTe1by8o5aVwQUoOPa+UGGK2Ufqh1
DyB9Kx53ta1KcPj+atoPUXdpXD/snszw9V5hxX+IIRZFhx3ZISmxzOqoMGztBlRu
Cr5Bk0jcZqtC1+qxynADBF5gcfHIecAgPwn0x2clsYROhRqa3h+nVG77dpSlrekt
+twe0jRR80N1Aw0Xt+Si+A==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 5904)
`pragma protect data_block
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
`pragma protect end_protected



