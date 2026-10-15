"""Prepare a small TD overlay; vendor/IP files remain referenced in the sealed old project."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil, xml.etree.ElementTree as ET

REPO=Path(__file__).resolve().parents[3]
OLD=REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys'
PROJECT=REPO/'fpga/custom_project/sc520-pixel17'
RTL=REPO/'fpga/rtl/sc520-card-recognition'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def write(p,s):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
def once(s,a,b):
    assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)

def make(destination,snapshot=False):
    destination=destination.resolve()
    sources=sorted((RTL/'pixel14').glob('*.v'))+sorted((RTL/'items14').glob('*.v'))+[RTL/n for n in ('card_template_rom.v','card_result_filter.v')]
    sources += [PROJECT/'overlay/pixel14_color_pipeline.v']
    sources += sorted((RTL/'color_diag').glob('*.v'))
    sources += sorted((RTL/'display17').glob('*.v'))
    mapping={}
    records=[]
    if snapshot:
        for name in ('prepare-pixel17.py','build-pixel17.ps1'):
            p=Path(__file__).with_name(name);q=destination/'tools'/name
            q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in sources:
            q=destination/'rtl'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            mapping[p.resolve()]=q;records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in (PROJECT/'overlay').glob('*'):
            q=destination/'overlay'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
    else: mapping={p.resolve():p.resolve() for p in sources}
    overlay=destination/'overlay'
    # The owned top selects the exact template generation. Never silently use
    # the legacy five-bit bank for a multi-variant scene candidate.
    top_text=(PROJECT/'overlay/design_top_wrapper.v').read_text(encoding='utf-8')
    template_paths=re.findall(r'\.TEMPLATE_FILE\("([^"]+)"\)',top_text)
    assert len(template_paths)==1,template_paths
    template=Path(template_paths[0]).resolve()
    template.relative_to(REPO/'assets/templates/sc520-card-recognition')
    assert template.is_file(),template
    if snapshot:
        target=destination/'templates.mem';shutil.copyfile(template,target)
        records.append({'Path':str(template),'Snapshot':str(target),'SHA256':sha(template)})
        template=target
        p=overlay/'design_top_wrapper.v'
        original_template=template_paths[0]
        write(p,p.read_text(encoding='utf-8').replace(original_template,template.as_posix()))
    for name in ('anlogic_logo_index.mem','anlogic_logo_palette.mem'):
        original=REPO/'assets/templates/sc520-card-recognition/display17'/name
        if snapshot:
            target=destination/name;shutil.copyfile(original,target)
            records.append({'Path':str(original),'Snapshot':str(target),'SHA256':sha(original)})
            p=overlay/'design_top_wrapper.v'
            write(p,p.read_text(encoding='utf-8').replace(original.as_posix(),target.as_posix()))
        else:records.append({'Path':str(original),'SHA256':sha(original)})
    replacement={
        (OLD/'user_source/hdl_source/design_top_wrapper.v').resolve():overlay/'design_top_wrapper.v',
        (OLD/'user_source/hdl_source/isp/isp_top.v').resolve():overlay/'isp_top.v',
        (OLD/'user_source/hdl_source/uics520_cfg/uicfgcs520.v').resolve():overlay/'uicfgcs520.v',
        (OLD/'user_source/hdl_source/uics500_cfg/uii2c.v').resolve():overlay/'uii2c.v',
        (OLD/'user_source/constraints_source/pin.adc').resolve():overlay/'pin.adc',
        (OLD/'td_project/camera_to_dsi_display.sdc').resolve():overlay/'pixel14.sdc'}
    refs=set()
    def xml(source,target):
        # TD writes a proprietary XML-like dialect with bare '&' and '::'.
        raw=source.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__TD_COLON__')
        root=ET.fromstring(raw);tree=ET.ElementTree(root)
        for group in root.find('Source_Files'):
            for file in list(group):
                original=(source.parent/file.attrib['Path']).resolve()
                rel=original.relative_to(OLD).as_posix()
                if any('/'+d+'/' in '/'+rel for d in ('roi','learning','quiz')) and original.name not in ('quiz_key_inputs.v','quiz_millisecond_tick.v'):
                    group.remove(file);continue
                resolved=replacement.get(original,original)
                assert resolved.is_file(),resolved
                file.attrib['Path']=resolved.as_posix();refs.add(resolved)
        group=root.find('Source_Files/Verilog')
        for i,p in enumerate(sources):
            p=mapping[p.resolve()];refs.add(p)
            el=ET.SubElement(group,'File',{'Path':p.as_posix()});info=ET.SubElement(el,'FileInfo')
            for k,v in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(200+i))]:ET.SubElement(info,'Attr',{'Name':k,'Val':v})
        ET.indent(tree)
        write(target,ET.tostring(root,encoding='unicode').replace('&amp;','&').replace('__TD_COLON__','::'))
    xml(OLD/'td_project/camera_to_dsi_display.al',destination/'td_project/camera_to_dsi_display.al')
    for stage in ('syn_1','phy_1'):
        oldrun=OLD/f'td_project/camera_to_dsi_display_Runs/{stage}'
        run=destination/f'td_project/camera_to_dsi_display_Runs/{stage}'
        xml(oldrun/'camera_to_dsi_display.prj',run/'camera_to_dsi_display.prj')
        settings=(oldrun/'settings.cfg').read_text(encoding='utf-8-sig')
        settings=settings.replace('../../../user_source/constraints_source/pin.adc',(overlay/'pin.adc').as_posix())
        settings=settings.replace('../../camera_to_dsi_display.sdc',(overlay/'pixel14.sdc').as_posix())
        settings=settings.replace('../../../user_source/',(OLD/'user_source').as_posix()+'/')
        write(run/'settings.cfg',settings)
        shutil.copyfile(oldrun/'camera_to_dsi_display.tcl',run/'camera_to_dsi_display.tcl')
    # Include collateral IP netlists, include files and ADC/SDC inputs in hashes.
    external=set(refs)
    for base in (OLD/'user_source',OLD/'td_project/al_ip'):
        external.update(p for p in base.rglob('*') if p.is_file() and p.suffix.lower() not in ('.bit','.db','.log','.wlf'))
    for p in sorted(external):
        records.append({'Path':str(p),'SHA256':sha(p)})
    for r in records:
        if 'Snapshot' in r:r['SnapshotSHA256']=sha(r['Snapshot'])
    result={'CreatedAt':datetime.datetime.now().astimezone().isoformat(),'Owner':'SC520 recovery /root/build_impl',
        'SourceProject':str(OLD),'Project':str(destination),'Snapshot':snapshot,'Files':records,
        'ManifestSources':[str(p) for p in sorted(refs)],'HardwareValidated':False}
    save(destination/'inputs.json',result)
    print(f'PIXEL14_PREPARED project={destination} refs={len(refs)} hashes={len(records)}')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--snapshot',type=Path);args=ap.parse_args()
    if args.snapshot:
        assert PROJECT.exists();args.snapshot.mkdir(parents=True,exist_ok=False);make(args.snapshot,True)
    else:
        assert PROJECT.is_dir(),'Create owned pixel17 overlay through start-display17.py first'
        make(PROJECT)
