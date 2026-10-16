"""Create only the D057-owned candidate files; keep every previous candidate intact."""
from pathlib import Path
import datetime, hashlib, json, re, subprocess

ROOT=Path(__file__).resolve().parents[3]
OWNER='01a144c7-e802-7272-a29d-a8159f5ec84b /root T023'
BASE='9f670bc80f07ea178fa6a1787683bde7ca60b9d3'
RTL=ROOT/'fpga/rtl/sc520-card-recognition'
SCRIPTS=Path(__file__).resolve().parent
E=ROOT/'evidence/sc520-card-recognition/timing23'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def write(p,s):
    if p.exists():
        assert read(p)==s,p
        return
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
def read(p): return p.read_text(encoding='utf-8-sig')
def once(s,a,b):
    assert s.count(a)==1,(a,s.count(a))
    return s.replace(a,b)
def main():
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()==BASE
    assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT).decode().strip()=='task/sc520-card-recognition'
    recovery=Path('E:/juan/FPGA/learning/sc520-contest-roadmap/board-t023-recovery-20261016.json')
    old=json.loads(read(recovery))
    for x in old['TrackedFiles']: assert sha(x['Path'])==x['SHA256'],x['Path']
    protected=json.loads(read(ROOT/'evidence/sc520-card-recognition/audio22/start.json'))['Protected']
    for x in protected: assert sha(x['Path'])==x['SHA256'],x['Path']
    start={'At':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'Owner':OWNER,'BaseCommit':BASE,'Recovery':{'Path':str(recovery),'SHA256':sha(recovery)},
        'TrackedFilesVerified':len(old['TrackedFiles']),'Protected':protected,
        'BitGenerationAllowed':False,'HardwareValidated':False}
    if not (E/'start.json').exists():write(E/'start.json',json.dumps(start,ensure_ascii=False,indent=2)+'\n')
    else:assert json.loads(read(E/'start.json'))['BaseCommit']==BASE

    # A single existing first stage feeds the original second stage and nine
    # preserved second-stage copies. No additional cycle or independent meta FF.
    s=read(RTL/'pixel14/pixel14_pipeline.v').replace('module pixel14_pipeline','module pixel23_pipeline',1)
    s=once(s,'reg [1:0] capture_reset,display_reset;',
        '(* preserve *) reg [1:0] capture_reset;\n    reg [1:0] display_reset;\n'
        '    // TD SWUG106 4.2.14: preserve prevents equivalent FF merging.\n'
        '    (* preserve *) reg [8:0] capture_release;\n'
        '    always @(posedge capture_clk or negedge rst_n)\n'
        "        if(!rst_n) capture_release<=0; else capture_release<={9{capture_reset[0]}};")
    # Partition by consumers. The original crst remains for local bookkeeping.
    for instance,bit in [('capture',0),('scene',1),('blocks',2),('shape_guard',3),('block_confirmation',4),('confirmation',5)]:
        pattern=r'(\b'+instance+r'\s*\(\s*\.clk\(capture_clk\),\.rst_n\()crst(\))'
        s,n=re.subn(pattern,lambda m:m[1]+f'capture_release[{bit}]'+m[2],s);assert n==1,(instance,n)
    s,n=re.subn(r'(\bmatcher\s*\(\s*\.clk\(capture_clk\),\.rst_n\()crst(\))',
        lambda m:m[1]+'capture_release[6]'+m[2],s);assert n==2
    s=s.replace('pixel14_color_observer #','pixel23_color_observer #')
    s=once(s,'.clk(capture_clk),.rst_n(crst),.flush(detector_flush),.frame_start(in_frame_start)',
        '.clk(capture_clk),.rst_n(crst),.diagnostics_rst_n(capture_release[7]),.join_rst_n(capture_release[8]),.flush(detector_flush),.frame_start(in_frame_start)')
    write(RTL/'timing23/pixel23_pipeline.v',s)
    s=read(RTL/'color_diag/pixel14_color_observer.v').replace('module pixel14_color_observer','module pixel23_color_observer',1)
    s=once(s,'input wire clk,rst_n,flush,','input wire clk,rst_n,diagnostics_rst_n,join_rst_n,flush,')
    s=once(s,'.clk(clk),.rst_n(rst_n),.flush(flush),.in_sof(frame_start)',
        '.clk(clk),.rst_n(diagnostics_rst_n),.flush(flush),.in_sof(frame_start)')
    s=once(s,'.clk(clk),.rst_n(rst_n),.flush(flush),.color_event',
        '.clk(clk),.rst_n(join_rst_n),.flush(flush),.color_event')
    write(RTL/'timing23/pixel23_color_observer.v',s)

    # Predecode original input coordinates alongside the processing register.
    s=read(RTL/'color_diag/pixel14_color_diag_osd.v').replace('module pixel14_color_diag_osd','module pixel23_color_diag_osd',1)
    s=s.replace("VERSION=16'h0114","VERSION=16'h0220")
    a=s.index('    wire region=');b=s.index('    function [7:0] digit;',a)
    coord=s[a:b].replace('wire region=','wire region_next=').replace('reg [2:0] row;reg [3:0] dy;','reg [2:0] row_next;reg [3:0] dy_next;')
    coord=re.sub(r'\brow=', 'row_next=',coord);coord=re.sub(r'\bdy=', 'dy_next=',coord)
    coord=coord.replace('wire [6:0] column=dx[9:3];','wire [6:0] column_next=dx[9:3];')
    ca=s.index('    wire center_mark=');cb=s.index('    always @(posedge clk',ca)
    marks=s[ca:cb].replace('wire center_mark=','wire center_next=').replace('wire paper_mark=','wire paper_next=')
    coord+=marks+'''    reg region,center_mark,paper_mark;
    reg [5:0] row_select;
    reg [6:0] column;
    reg [2:0] dot_x;
    reg [3:0] dy;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin region<=0;center_mark<=0;paper_mark<=0;row_select<=0;column<=0;dot_x<=0;dy<=0;end
        else begin
            region<=region_next;center_mark<=center_next;paper_mark<=paper_next;
            row_select<=6'b000001<<row_next;column<=column_next;dot_x<=dx[2:0];dy<=dy_next;
        end
'''
    s=s[:a]+coord+s[b:ca]+s[cb:]
    a=s.index('    reg [7:0] character;');b=s.index('    function [4:0] glyph;',a)
    entries=re.findall(r"10'd(\d+):character=(.*?);",s[a:b]);assert len(entries)>300
    generated='    reg [7:0] row_character[0:5];\n'
    for row in range(6):
        generated+=f'    always @* begin row_character[{row}]=" ";case(column)\n'
        for number,value in entries:
            n=int(number)
            if n//128==row:generated+=f"        7'd{n%128}:row_character[{row}]={value};\n"
        generated+=f'        default:row_character[{row}]=" ";\n    endcase end\n'
    generated+='    wire [7:0] character='+ ' |\n        '.join(f'({{8{{row_select[{i}]}}}} & row_character[{i}])' for i in range(6))+';\n'
    s=s[:a]+generated+s[b:]
    s=s.replace('dx[2:0]<5','dot_x<5').replace('dots[4-dx[2:0]]','dots[4-dot_x]')
    s=s.replace('// Generated fixed layout. Existing768x72 diagnostic region; six8x12 rows.',
        '// T023: coordinate register at N, RGB register at N+1. One packet snapshot.\n// Six row-local character selectors; original six 8x12 rows and glyphs retained.')
    write(RTL/'timing23/pixel23_color_diag_osd.v',s)
    s=read(RTL/'audio22/pixel22_compositor.v').replace('module pixel22_compositor','module pixel23_compositor',1)
    s=once(s,'pixel14_color_diag_osd #','pixel23_color_diag_osd #')
    s=once(s,'.frame_start(in_frame_start),.pixel_x(p_x),.pixel_y(p_y)',
        '.frame_start(in_frame_start),.pixel_x(in_x),.pixel_y(in_y)')
    s=s.replace('// Its pixel input is stage1, so it renders that new snapshot at N+1.',
        '// It predecodes original coordinates at N and renders the new snapshot at N+1.')
    write(RTL/'timing23/pixel23_compositor.v',s)

    project=ROOT/'fpga/custom_project/sc520-timing23'
    for p in sorted((ROOT/'fpga/custom_project/sc520-audio22/overlay').iterdir()):
        s=read(p)
        if p.name=='design_top_wrapper.v':
            s=once(s,'pixel22_compositor #','pixel23_compositor #')
            s=once(s,'pixel14_pipeline #','pixel23_pipeline #')
        write(project/'overlay'/p.name,s)
    s=read(SCRIPTS/'prepare-audio22.py').replace('sc520-audio22','sc520-timing23').replace('prepare-audio22.py','prepare-timing23.py').replace('build-audio22.ps1','build-timing23.ps1')
    s=s.replace("    mapping={}\n","    sources += sorted((RTL/'timing23').glob('*.v'))\n    mapping={}\n")
    s=s.replace('01a14030-32d9-78f2-b274-91a370cc9ff0 /root T022',OWNER).replace('T022','T023')
    write(SCRIPTS/'prepare-timing23.py',s)
    s=read(SCRIPTS/'build-audio22.ps1').replace('prepare-audio22.py','prepare-timing23.py').replace('T022','T023')
    s=s.replace('01a14030-32d9-78f2-b274-91a370cc9ff0 /root T023',OWNER)
    s=s.replace("@('X:','Y:','Z:','W:','V:')","@('V:','U:','T:','S:','R:')")
    # Release only this mapping, even if another process changes the alias.
    s=s.replace('    & subst.exe $drive /d',"    $owned=@(& subst.exe) | Where-Object {$_ -eq ($drive+'\\: => '+$run.Replace('/','\\'))}\n    if($owned){& subst.exe $drive /d}else{Write-Warning 'Mapping changed; leave it intact'}")
    write(SCRIPTS/'build-timing23.ps1',s)
    s=read(SCRIPTS/'register-audio22.py').replace('-sc520-audio22-','-sc520-timing23-').replace('T022','T023')
    write(SCRIPTS/'register-timing23.py',s)
    log=ROOT/'memory/branches/sc520-card-recognition.md'
    s=read(log).replace('- 状态：等待主对话审核','- 状态：进行中',1)
    a=s.index('- 负责人：');b=s.index('\n',a);s=s[:a]+'- 负责人：'+OWNER+'；新聊天接续 D057/T023，当前主 01a14468-1741-70a2-aea6-757eb183382f'+s[b:]
    a=s.index('- 结束时间：');b=s.index('\n',a);s=s[:a]+'- 结束时间：T023进行中；T022拒收封存保持'+s[b:]
    a=s.index('\n## D054')
    note='''
## D057/T023启动（2026-10-16）

从干净9f670bc沿用原工作树和分支，接替失败01a144ae；当前主D059仅更新负责人，D057技术范围不变。已核恢复快照7628跟踪文件及763保护文件SHA。主库现行文档优先于旧工作树总文档；不重建原工程，不reset/stash/切分支，XYZ已由主解除。

新增timing23局部候选：同capture_reset[0]驱动9个preserve第二级分区，原第二级保留；诊断原始坐标在N预译码、6行字符分组在N+1输出，单快照、六层N+5保持。只从本机TD6.2.1随附SWUG106第4.2.14确认preserve防合并，尚须实际网表确认。54拍ISP、音频冻结代码、时钟/例外与厂商DDR均保持。当前仅实现，仿真/物理待验证，禁止bitgen/下载。

下一步：针对性复位/首帧/坏帧/停采/payload以及完整720p/四键/音频回归，然后独立新候选综合布局布线，复核全部ROM、原24链及新增复位链、四mailbox和四类全局时序。
'''
    log.write_text(s[:a]+'\n'+note+s[a:],encoding='utf-8')
    print(json.dumps({'Owner':OWNER,'TrackedVerified':len(old['TrackedFiles']),'ProtectedVerified':len(protected),'Candidate':str(project)}))
if __name__=='__main__':main()
