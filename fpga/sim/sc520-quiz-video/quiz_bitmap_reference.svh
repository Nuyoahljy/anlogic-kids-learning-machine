// Local SimSun 16px, monochrome threshold 128; source SHA256 1526AC24375F51F6EB73BC2D3F8072DBE4A80A3A65217677C9D9A84F67DAB2AB.

// Full-bitmap reference: same font asset, independent pixel addressing in TB.
function automatic [255:0] quiz_ref_bitmap(input integer glyph_id);
begin
quiz_ref_bitmap=0;
case(glyph_id)
1: quiz_ref_bitmap=256'h0000000000000000FFFE00000000000000000000000000000000000000000000;
2: quiz_ref_bitmap=256'h000000007FFC00000000000000003FF800000000000000000000FFFE00000000;
3: quiz_ref_bitmap=256'h7FFC008000800100010003400520091011082104410481000100010001000000;
4: quiz_ref_bitmap=256'h1000100010001FFC1000200020003FF8000800080008FFC80008000800500020;
5: quiz_ref_bitmap=256'hFFFE0440044004407FFC4444444444444AA44A94511442044004401440080000;
6: quiz_ref_bitmap=256'h7FF8000800080808040802080208006801880E08700820080008005000200000;
7: quiz_ref_bitmap=256'h088008400840100017FC3000300852089208111011101110112010201FFE1000;
8: quiz_ref_bitmap=256'h084008400840104017FC304030E050E091501150124815F41842104010401040;
9: quiz_ref_bitmap=256'h09000900090011FE12803280348050F890801080108010FC1080108010801080;
10: quiz_ref_bitmap=256'h090009F00A1017FC1A24324433FC5080914416A81130166810A8112416A21040;
11: quiz_ref_bitmap=256'h0100110011001FF8210041000100FFFE044004400440084008421042203EC000;
12: quiz_ref_bitmap=256'h0400020001000100010002800280028004400440082008201010201040088006;
13: quiz_ref_bitmap=256'h04200420042004203FFC042004200420042004207FFE00000420081010082004;
14: quiz_ref_bitmap=256'h0100010001007FFC410441044104428442444424481450144004400440144008;
15: quiz_ref_bitmap=256'hFFFE010001003FF8210821083FF821082108FFFE200820082008202820100000;
16: quiz_ref_bitmap=256'h0100010021082108210821083FF801080100010041044104410441047FFC0004;
17: quiz_ref_bitmap=256'h00400440042008201010200840049FE204200420042008200820102021404080;
18: quiz_ref_bitmap=256'h1000100011FC104410441E44F044104410441244144418841084010402280410;
19: quiz_ref_bitmap=256'h00047F044104412441247F2410241024FF24112411241124210421044A148408;
20: quiz_ref_bitmap=256'h0004FF840804102422244124FFA408A4082408247F24082408040F84F8144008;
21: quiz_ref_bitmap=256'h0404240424043FA444240424FFE4042404243FA424A424A42684250404140408;
22: quiz_ref_bitmap=256'h101008100820FFFE00003E08224822483E48224822483E48220822082A282410;
23: quiz_ref_bitmap=256'h100010001000107CFE4412441244124412441244124412442244227C4A448400;
24: quiz_ref_bitmap=256'h0200044008201FF002007FFC082010902308CC4601800610182000C007007800;
25: quiz_ref_bitmap=256'h01001110110822003FFC0200040007F80A080908111010A0204040A003181C06;
26: quiz_ref_bitmap=256'h1FF01010101010101010101010101FF010100000082008101008200440040000;
27: quiz_ref_bitmap=256'h7FFE001000101F10111011101110111011101F10111000100010005000200000;
28: quiz_ref_bitmap=256'h1FF01010101010101FF00000FFFE080010001FF000100010001000A000400000;
29: quiz_ref_bitmap=256'h3FFC200420042FF42004200427E424242424242427E424242004201420080000;
30: quiz_ref_bitmap=256'h04000E007800087C0844FF44084418441C442A442A444844887C084408000800;
31: quiz_ref_bitmap=256'h00003FF82008200827C82448244824482448244827C8200820083FF820080000;
32: quiz_ref_bitmap=256'h0000000000000000000000000000000000000000000000000000000000000000;
33: quiz_ref_bitmap=256'h7FFC40044FE448244FE440045FF45014511451145294444448247FFC40040000;
34: quiz_ref_bitmap=256'h020002000400FFFE080008401040304057FC904010401040104010401FFE1000;
35: quiz_ref_bitmap=256'h100010001FFC20005FF090101FF010101FF004000FF01820644003801C70E00E;
36: quiz_ref_bitmap=256'h04000400FFFE0800080013F810103020504097FE104010401040104011401080;
37: quiz_ref_bitmap=256'h22081108111000207FFE400280041FE000400180FFFE01000100010005000200;
38: quiz_ref_bitmap=256'h020001007FFE400280041FF0000000007FFC044004400440084408441044603C;
39: quiz_ref_bitmap=256'h020001007FFE4002888404800480108008800880FFFE01400220041018086004;
40: quiz_ref_bitmap=256'h00003FF0001000100010201020103FF02000200020002004200420041FFC0000;
41: quiz_ref_bitmap=256'h0100111009207FFE40029FF410101FF001003FF8210821082128211001000100;
42: quiz_ref_bitmap=256'h3FF0201020103FF0200420041FFC000008200820FFFE08201020202040200000;
43: quiz_ref_bitmap=256'h0048004400440040FFFE004000403E4008400840082008220F12780A20060002;
44: quiz_ref_bitmap=256'h0100210811080910092001007FF80008000800083FF80008000800087FF80008;
45: quiz_ref_bitmap=256'h0000000000000000000007E00000000000000000000000000000000000000000;
46: quiz_ref_bitmap=256'h7F8412041208121012221202FFC4120812101222120222042208421082600000;
47: quiz_ref_bitmap=256'h0000002000600040004000800080018001000100020002000600040000000000;
48: quiz_ref_bitmap=256'h0000000001800240042004200420042004200420042002400180000000000000;
49: quiz_ref_bitmap=256'h00000000008003800080008000800080008000800080008003E0000000000000;
50: quiz_ref_bitmap=256'h0000000003C004600420002000000040000000000000002007E0000000000000;
51: quiz_ref_bitmap=256'h0000000003C004600420002000400180004000200420046003C0000000000000;
52: quiz_ref_bitmap=256'h00000000004000C000C0014000400240044007F00040004001F0000000000000;
53: quiz_ref_bitmap=256'h0000000007E000000000000003C00460002000200420044003C0000000000000;
54: quiz_ref_bitmap=256'h00000000018002400400040005C00660042004200420024001C0000000000000;
55: quiz_ref_bitmap=256'h0000000007E00400000000000000000000000100010001000100000000000000;
56: quiz_ref_bitmap=256'h0000000003C0066004200420034001C0004004200420066003C0000000000000;
57: quiz_ref_bitmap=256'h0000000003800240042004200420066003A00020004002400380000000000000;
58: quiz_ref_bitmap=256'h08400840104023FC4840084017FE3010501097FE101012101110111010501020;
59: quiz_ref_bitmap=256'h010001007FFC0100028004400A203118C0060100088848844812481287F00000;
60: quiz_ref_bitmap=256'h10100820044000001FF01010101010101FF01010010008844892481287F00000;
61: quiz_ref_bitmap=256'h0050004800403FFE2040204020443E4422442228222822122A32444A40868102;
62: quiz_ref_bitmap=256'h004800440040FFFE004000403E442244224422283E2800120732784A20860302;
63: quiz_ref_bitmap=256'h1090108810881080FCBC13C01080148818883090D060104410A41114520C2004;
64: quiz_ref_bitmap=256'h1008108810481228FA28120812081A083208D208121012981324122450422082;
65: quiz_ref_bitmap=256'h10201020102011FCFC20102013FE1008180833FED00810881048100850282010;
66: quiz_ref_bitmap=256'h10401020102013FEFA02144410401BFE3088D088110810D01020105050882304;
67: quiz_ref_bitmap=256'h1080108010F81108FA1015FC112419243124D12417FE10501050108851042602;
68: quiz_ref_bitmap=256'h200027FC240424A4F91022082040284037FCE04020E0215022482C46A0404040;
69: quiz_ref_bitmap=256'h10401020102013FEFA02149411081A043000D1FC102010201020102057FE2000;
70: quiz_ref_bitmap=256'h100013FC110811F8FD0811F8110E17F8180837BCD0A412A41128129054A82846;
71: quiz_ref_bitmap=256'h207827C022482150FBFC215022482C0633F8E248224823F822482248A3F84208;
72: quiz_ref_bitmap=256'h084008404840488048FE49084A88488848885850685048200850088809040A02;
73: quiz_ref_bitmap=256'h204010400040FE8020FE21083E88248824882450245024204450548889040202;
74: quiz_ref_bitmap=256'h1040104010401080FEFE1108128810887C8844504450442044507C8845040202;
75: quiz_ref_bitmap=256'h082049202A20083EFF442A44494488A41028FE2822104210642818283444C282;
76: quiz_ref_bitmap=256'h100008047F78004022401440FF7E084808487F4808482A484948888828881108;
77: quiz_ref_bitmap=256'h020001000100FFFE04000400040007F004100410041008100810101020A04040;
78: quiz_ref_bitmap=256'h200023FC2204220422042204220423FC2204220422042204220423FC22042000;
79: quiz_ref_bitmap=256'h000800087C08440845FE440844087C0844884448444844087C08440800280010;
80: quiz_ref_bitmap=256'h00001FF0101010101FF0101010101FF0044044442444144814500440FFFE0000;
81: quiz_ref_bitmap=256'h01000100010001007FFC03800540054009201110210841048102010001000100;
82: quiz_ref_bitmap=256'h0100010001003FF8010001000100FFFE03800540092011102108C10601000100;
83: quiz_ref_bitmap=256'h01000100010001007FFC0380054005400920111021084FE48102010001000100;
84: quiz_ref_bitmap=256'h100011F011101110FD10111031103910551055109110111211121212120E1400;
85: quiz_ref_bitmap=256'h01000100FFFE010001003FF82108210821083FF82388054009203118C1060100;
86: quiz_ref_bitmap=256'h0100010001007FFC0100111009100920FFFE0380054009203118C10601000100;
87: quiz_ref_bitmap=256'h100011FC10001000FC0013FE3020382055285524922412221422102010A01040;
88: quiz_ref_bitmap=256'h01007FFC40040400FFFE08201E4003C03C380100FFFE054009203118C1060100;
89: quiz_ref_bitmap=256'h1110111017FC1110FC0013F832083BF8560853F8904017FC10A0111012081406;
90: quiz_ref_bitmap=256'h00804080208020FC010409080A4014401040E0A020A021102110220824040802;
91: quiz_ref_bitmap=256'h01000100010001001100110011F81100110011001100110011001100FFFE0000;
92: quiz_ref_bitmap=256'h00007FFC0100010001000100110011F8110011001100110011001100FFFE0000;
93: quiz_ref_bitmap=256'h000427C414441454855445544554155415542554E55421042284224424140808;
94: quiz_ref_bitmap=256'h0040204017FC104083F8404047FE100013F82208E3F8220823F8220822280210;
95: quiz_ref_bitmap=256'h27FE1420144085FC450445FC150415FC2524E42024A829242A2230A000400000;
96: quiz_ref_bitmap=256'h0080204017FC1404800043F8404013F8124823F8E24823F82000211022080404;
97: quiz_ref_bitmap=256'h10801080508050FC7D545254905410941C94F124522410441044108411281010;
98: quiz_ref_bitmap=256'h084008480844484428402FFE08400840184028A0C8A00890091009080A040C02;
99: quiz_ref_bitmap=256'hFFFE000000004FE4492449244FE44924492449244FE4400440047FFC00040000;
100: quiz_ref_bitmap=256'h3FF82008200820083FF82008200820083FF820082008200820083FF820080000;
101: quiz_ref_bitmap=256'h080008FC08840884FE8408FC18841C842A842AFC488488840884088408FC0884;
102: quiz_ref_bitmap=256'h20002000207C7E444844884408440844FF44084414441444227C224442008000;
103: quiz_ref_bitmap=256'h00400040FC7C1084110822FE3C92649264FEA492249224FE3C922512210A0204;
104: quiz_ref_bitmap=256'h3FF80000000000000000FFFE0100010011101108210441028102050002000000;
105: quiz_ref_bitmap=256'h082008207EFC08201C702AA8C82600003FF800000000FFFE0100111025084204;
106: quiz_ref_bitmap=256'h04000E0078FC08840884FF84088418841CFC2A842A0048488844088408820902;
107: quiz_ref_bitmap=256'h08201C20F07C10841148FC30102030483990543E544291A41018101010601180;
108: quiz_ref_bitmap=256'h020001007FFE400288241010200800001FF0010001000100010001007FFC0000;
109: quiz_ref_bitmap=256'h104010403F7E2890450882800C603018CFE600001FF01010101010101FF01010;
110: quiz_ref_bitmap=256'h010001003FF8010001007FFE420284241FC0018006103FF80108112025104208;
111: quiz_ref_bitmap=256'h1000100021FC24204420F820102020204020FC20402000201C20E02043FE0000;
112: quiz_ref_bitmap=256'h10201020202027FE4420F82011FC20004000FDFC410401041D04E10441FC0104;
113: quiz_ref_bitmap=256'h1020102021FC24204420FBFE100220944050FD10409003FE1C28E04440820302;
114: quiz_ref_bitmap=256'h7FFC44447FFC01007FFC01001FF010101FF010101FF010101FF01010FFFE0000;
115: quiz_ref_bitmap=256'h01007900491E4B924912791249124FD2491279124A1A4A944FD04A5048109810;
116: quiz_ref_bitmap=256'h080008001FE020204040BFF82108210821083FF820002002200220021FFE0000;
117: quiz_ref_bitmap=256'h08200820FFFE08200480248024FC24A0251000003FF8244824482448FFFE0000;
118: quiz_ref_bitmap=256'h080008001FE020204040BFF8210821083FF8210821083FF82108410841288010;
119: quiz_ref_bitmap=256'h20202020782049FC91247D24552455247DFC552454207C28542457FE45028C00;
120: quiz_ref_bitmap=256'h004020401040104000400040F7FE104010401040104010401440184010400040;
121: quiz_ref_bitmap=256'h004020401040104000400040F040104010A010A010A015101910120804040802;
122: quiz_ref_bitmap=256'h200011FC110401040104F104110411FC11041000149018881104020204020000;
123: quiz_ref_bitmap=256'h002820241024102007FE0020F02017E0112011101110151019CA170A02060002;
124: quiz_ref_bitmap=256'h0040404027FC204003F80040E7FE200023F8220823F822082BF8320822280210;
125: quiz_ref_bitmap=256'h0100010001003FF801000100FFFE01000100110011F811001100290047FE8000;
126: quiz_ref_bitmap=256'h2040204020A0FCA0411052089406FD10112011401D80F1005104110410FC1000;
127: quiz_ref_bitmap=256'h03F82208120813F802080208F3F8124412281210128813041204280047FE0000;
128: quiz_ref_bitmap=256'h001000F83F000100FFFE01001FF011101FF011101FF001003FF80100FFFE0000;
129: quiz_ref_bitmap=256'h21102110391027FC41107910AFFE2000FBF82208220823F82A08320823F80208;
130: quiz_ref_bitmap=256'h201020103B7C211441FE7A14A27C2710F97C251025FE22102A10350028FE0000;
131: quiz_ref_bitmap=256'h200017FC00044004400447C44444444444444444444447C44444400440144008;
132: quiz_ref_bitmap=256'h200017FC00044104410441045FF4410443844544492451144104410440144008;
133: quiz_ref_bitmap=256'h00207DFC448848504BFE500049FC490445FC450445FC682053FE402040204020;
134: quiz_ref_bitmap=256'hFFFE0200020004003FF82448244827C82448244827C8244824483FF820080000;
135: quiz_ref_bitmap=256'h020001003FF8000008200440FFFE00001FF0101010101FF0101010101FF01010;
136: quiz_ref_bitmap=256'h100011FE50205C4051FC5104FF2401241124552455245544845008883104C202;
137: quiz_ref_bitmap=256'h3EFE22103E20227C3E440054FF54085408542F282844288258004FFE80000000;
138: quiz_ref_bitmap=256'h100008FE7F102220147C7F444454485452544454485451544228442488423082;
139: quiz_ref_bitmap=256'h0020F82008504850488849044AFA7C00044404241D24E4A8448804102BFE1000;
140: quiz_ref_bitmap=256'h04403FF804400440FFFE01001FF0111011101FF0111011101FF0044008201010;
141: quiz_ref_bitmap=256'h0000100010001000100010001000100010001000000000001000100000000000;
142: quiz_ref_bitmap=256'h0000000000000000000000003000300010002000000000000000000000000000;
143: quiz_ref_bitmap=256'h0000000000000000000030003000000030003000000000000000000000000000;
endcase
end
endfunction
function automatic integer quiz_ref_text(input integer text_id,input integer position);
begin
quiz_ref_text=0;
case(text_id)
0: begin
case(position)
default: quiz_ref_text=0;
endcase
end
1: begin
case(position)
0: quiz_ref_text=58;
1: quiz_ref_text=84;
2: quiz_ref_text=89;
3: quiz_ref_text=43;
default: quiz_ref_text=0;
endcase
end
2: begin
case(position)
0: quiz_ref_text=68;
1: quiz_ref_text=110;
2: quiz_ref_text=89;
3: quiz_ref_text=43;
default: quiz_ref_text=0;
endcase
end
3: begin
case(position)
0: quiz_ref_text=131;
1: quiz_ref_text=109;
2: quiz_ref_text=89;
3: quiz_ref_text=43;
default: quiz_ref_text=0;
endcase
end
4: begin
case(position)
0: quiz_ref_text=89;
1: quiz_ref_text=43;
2: quiz_ref_text=42;
3: quiz_ref_text=41;
default: quiz_ref_text=0;
endcase
end
5: begin
case(position)
0: quiz_ref_text=137;
1: quiz_ref_text=28;
default: quiz_ref_text=0;
endcase
end
6: begin
case(position)
0: quiz_ref_text=17;
1: quiz_ref_text=75;
default: quiz_ref_text=0;
endcase
end
7: begin
case(position)
0: quiz_ref_text=93;
1: quiz_ref_text=123;
2: quiz_ref_text=86;
3: quiz_ref_text=95;
4: quiz_ref_text=143;
5: quiz_ref_text=14;
6: quiz_ref_text=114;
7: quiz_ref_text=99;
8: quiz_ref_text=134;
9: quiz_ref_text=142;
10: quiz_ref_text=105;
11: quiz_ref_text=91;
12: quiz_ref_text=92;
13: quiz_ref_text=43;
14: quiz_ref_text=120;
15: quiz_ref_text=17;
default: quiz_ref_text=0;
endcase
end
8: begin
case(position)
0: quiz_ref_text=70;
1: quiz_ref_text=10;
2: quiz_ref_text=86;
3: quiz_ref_text=95;
4: quiz_ref_text=143;
5: quiz_ref_text=39;
6: quiz_ref_text=79;
7: quiz_ref_text=99;
8: quiz_ref_text=134;
9: quiz_ref_text=142;
10: quiz_ref_text=58;
11: quiz_ref_text=39;
12: quiz_ref_text=97;
13: quiz_ref_text=139;
14: quiz_ref_text=72;
default: quiz_ref_text=0;
endcase
end
9: begin
case(position)
0: quiz_ref_text=135;
1: quiz_ref_text=136;
2: quiz_ref_text=89;
3: quiz_ref_text=64;
4: quiz_ref_text=143;
5: quiz_ref_text=108;
6: quiz_ref_text=132;
11: quiz_ref_text=66;
12: quiz_ref_text=130;
13: quiz_ref_text=89;
14: quiz_ref_text=64;
15: quiz_ref_text=143;
16: quiz_ref_text=115;
17: quiz_ref_text=83;
18: quiz_ref_text=69;
19: quiz_ref_text=21;
default: quiz_ref_text=0;
endcase
end
10: begin
case(position)
0: quiz_ref_text=135;
1: quiz_ref_text=136;
2: quiz_ref_text=89;
3: quiz_ref_text=64;
4: quiz_ref_text=143;
5: quiz_ref_text=71;
6: quiz_ref_text=73;
11: quiz_ref_text=66;
12: quiz_ref_text=130;
13: quiz_ref_text=89;
14: quiz_ref_text=64;
15: quiz_ref_text=143;
16: quiz_ref_text=115;
17: quiz_ref_text=83;
18: quiz_ref_text=69;
19: quiz_ref_text=21;
default: quiz_ref_text=0;
endcase
end
11: begin
case(position)
0: quiz_ref_text=135;
1: quiz_ref_text=136;
2: quiz_ref_text=89;
3: quiz_ref_text=64;
4: quiz_ref_text=143;
5: quiz_ref_text=74;
6: quiz_ref_text=133;
11: quiz_ref_text=66;
12: quiz_ref_text=130;
13: quiz_ref_text=89;
14: quiz_ref_text=64;
15: quiz_ref_text=143;
16: quiz_ref_text=115;
17: quiz_ref_text=83;
18: quiz_ref_text=69;
19: quiz_ref_text=21;
default: quiz_ref_text=0;
endcase
end
12: begin
case(position)
0: quiz_ref_text=124;
1: quiz_ref_text=73;
2: quiz_ref_text=114;
3: quiz_ref_text=106;
4: quiz_ref_text=81;
5: quiz_ref_text=142;
6: quiz_ref_text=62;
7: quiz_ref_text=18;
8: quiz_ref_text=67;
9: quiz_ref_text=20;
10: quiz_ref_text=131;
11: quiz_ref_text=109;
12: quiz_ref_text=89;
13: quiz_ref_text=43;
default: quiz_ref_text=0;
endcase
end
13: begin
case(position)
0: quiz_ref_text=68;
1: quiz_ref_text=110;
2: quiz_ref_text=37;
3: quiz_ref_text=6;
4: quiz_ref_text=143;
5: quiz_ref_text=73;
6: quiz_ref_text=12;
7: quiz_ref_text=106;
8: quiz_ref_text=81;
9: quiz_ref_text=121;
10: quiz_ref_text=122;
11: quiz_ref_text=138;
12: quiz_ref_text=116;
13: quiz_ref_text=30;
14: quiz_ref_text=46;
15: quiz_ref_text=98;
default: quiz_ref_text=0;
endcase
end
14: begin
case(position)
0: quiz_ref_text=124;
1: quiz_ref_text=63;
2: quiz_ref_text=16;
3: quiz_ref_text=143;
default: quiz_ref_text=0;
endcase
end
15: begin
case(position)
0: quiz_ref_text=83;
1: quiz_ref_text=126;
2: quiz_ref_text=38;
3: quiz_ref_text=61;
4: quiz_ref_text=143;
5: quiz_ref_text=13;
6: quiz_ref_text=49;
7: quiz_ref_text=48;
8: quiz_ref_text=137;
9: quiz_ref_text=142;
10: quiz_ref_text=60;
11: quiz_ref_text=17;
default: quiz_ref_text=0;
endcase
end
16: begin
case(position)
0: quiz_ref_text=98;
1: quiz_ref_text=59;
2: quiz_ref_text=42;
3: quiz_ref_text=41;
4: quiz_ref_text=143;
5: quiz_ref_text=124;
6: quiz_ref_text=35;
7: quiz_ref_text=7;
default: quiz_ref_text=0;
endcase
end
17: begin
case(position)
0: quiz_ref_text=93;
1: quiz_ref_text=123;
2: quiz_ref_text=99;
3: quiz_ref_text=134;
4: quiz_ref_text=26;
5: quiz_ref_text=9;
6: quiz_ref_text=96;
7: quiz_ref_text=104;
8: quiz_ref_text=142;
9: quiz_ref_text=3;
10: quiz_ref_text=24;
11: quiz_ref_text=4;
12: quiz_ref_text=92;
13: quiz_ref_text=43;
14: quiz_ref_text=120;
15: quiz_ref_text=17;
default: quiz_ref_text=0;
endcase
end
18: begin
case(position)
0: quiz_ref_text=109;
1: quiz_ref_text=137;
2: quiz_ref_text=112;
3: quiz_ref_text=85;
4: quiz_ref_text=142;
5: quiz_ref_text=27;
6: quiz_ref_text=94;
7: quiz_ref_text=17;
8: quiz_ref_text=127;
9: quiz_ref_text=16;
10: quiz_ref_text=62;
11: quiz_ref_text=18;
12: quiz_ref_text=67;
13: quiz_ref_text=89;
14: quiz_ref_text=43;
default: quiz_ref_text=0;
endcase
end
19: begin
case(position)
0: quiz_ref_text=31;
1: quiz_ref_text=109;
2: quiz_ref_text=92;
3: quiz_ref_text=103;
4: quiz_ref_text=141;
5: quiz_ref_text=23;
6: quiz_ref_text=49;
7: quiz_ref_text=17;
8: quiz_ref_text=142;
9: quiz_ref_text=124;
10: quiz_ref_text=11;
11: quiz_ref_text=107;
12: quiz_ref_text=125;
13: quiz_ref_text=106;
14: quiz_ref_text=81;
default: quiz_ref_text=0;
endcase
end
20: begin
case(position)
0: quiz_ref_text=15;
1: quiz_ref_text=123;
2: quiz_ref_text=1;
3: quiz_ref_text=90;
4: quiz_ref_text=141;
5: quiz_ref_text=124;
6: quiz_ref_text=11;
7: quiz_ref_text=107;
8: quiz_ref_text=125;
9: quiz_ref_text=142;
10: quiz_ref_text=15;
11: quiz_ref_text=128;
12: quiz_ref_text=76;
13: quiz_ref_text=73;
14: quiz_ref_text=12;
default: quiz_ref_text=0;
endcase
end
21: begin
case(position)
0: quiz_ref_text=5;
1: quiz_ref_text=90;
2: quiz_ref_text=109;
3: quiz_ref_text=129;
4: quiz_ref_text=142;
5: quiz_ref_text=80;
6: quiz_ref_text=104;
7: quiz_ref_text=109;
8: quiz_ref_text=88;
9: quiz_ref_text=142;
10: quiz_ref_text=83;
11: quiz_ref_text=137;
12: quiz_ref_text=3;
13: quiz_ref_text=23;
14: quiz_ref_text=17;
default: quiz_ref_text=0;
endcase
end
22: begin
case(position)
0: quiz_ref_text=40;
1: quiz_ref_text=103;
2: quiz_ref_text=121;
3: quiz_ref_text=107;
4: quiz_ref_text=125;
5: quiz_ref_text=142;
6: quiz_ref_text=124;
7: quiz_ref_text=73;
8: quiz_ref_text=12;
9: quiz_ref_text=109;
10: quiz_ref_text=88;
default: quiz_ref_text=0;
endcase
end
23: begin
case(position)
0: quiz_ref_text=124;
1: quiz_ref_text=11;
2: quiz_ref_text=107;
3: quiz_ref_text=125;
4: quiz_ref_text=78;
5: quiz_ref_text=97;
6: quiz_ref_text=8;
7: quiz_ref_text=142;
8: quiz_ref_text=15;
9: quiz_ref_text=73;
10: quiz_ref_text=12;
11: quiz_ref_text=109;
12: quiz_ref_text=88;
default: quiz_ref_text=0;
endcase
end
24: begin
case(position)
0: quiz_ref_text=101;
1: quiz_ref_text=29;
2: quiz_ref_text=97;
3: quiz_ref_text=8;
4: quiz_ref_text=65;
5: quiz_ref_text=113;
6: quiz_ref_text=36;
7: quiz_ref_text=34;
8: quiz_ref_text=79;
9: quiz_ref_text=3;
10: quiz_ref_text=128;
11: quiz_ref_text=35;
12: quiz_ref_text=119;
13: quiz_ref_text=25;
default: quiz_ref_text=0;
endcase
end
25: begin
case(position)
0: quiz_ref_text=44;
1: quiz_ref_text=22;
2: quiz_ref_text=122;
3: quiz_ref_text=19;
4: quiz_ref_text=143;
default: quiz_ref_text=0;
endcase
end
26: begin
case(position)
0: quiz_ref_text=92;
1: quiz_ref_text=103;
2: quiz_ref_text=109;
3: quiz_ref_text=88;
4: quiz_ref_text=143;
default: quiz_ref_text=0;
endcase
end
27: begin
case(position)
0: quiz_ref_text=82;
1: quiz_ref_text=102;
2: quiz_ref_text=100;
3: quiz_ref_text=87;
default: quiz_ref_text=0;
endcase
end
28: begin
case(position)
0: quiz_ref_text=111;
1: quiz_ref_text=116;
2: quiz_ref_text=33;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
29: begin
case(position)
0: quiz_ref_text=111;
1: quiz_ref_text=116;
2: quiz_ref_text=77;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
30: begin
case(position)
0: quiz_ref_text=111;
1: quiz_ref_text=116;
2: quiz_ref_text=2;
3: quiz_ref_text=118;
4: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
31: begin
case(position)
0: quiz_ref_text=140;
1: quiz_ref_text=116;
2: quiz_ref_text=33;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
32: begin
case(position)
0: quiz_ref_text=140;
1: quiz_ref_text=116;
2: quiz_ref_text=77;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
33: begin
case(position)
0: quiz_ref_text=140;
1: quiz_ref_text=116;
2: quiz_ref_text=2;
3: quiz_ref_text=118;
4: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
34: begin
case(position)
0: quiz_ref_text=117;
1: quiz_ref_text=116;
2: quiz_ref_text=33;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
35: begin
case(position)
0: quiz_ref_text=117;
1: quiz_ref_text=116;
2: quiz_ref_text=77;
3: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
36: begin
case(position)
0: quiz_ref_text=117;
1: quiz_ref_text=116;
2: quiz_ref_text=2;
3: quiz_ref_text=118;
4: quiz_ref_text=46;
default: quiz_ref_text=0;
endcase
end
endcase
end
endfunction
