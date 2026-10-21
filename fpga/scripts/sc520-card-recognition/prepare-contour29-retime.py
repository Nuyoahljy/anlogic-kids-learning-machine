"""Prepare D0291 directly; no TD execution, inherited DB, or changes to frozen D0290."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil, subprocess, sys, xml.etree.ElementTree as ET

REPO=Path(__file__).resolve().parents[3]
OLD=REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys'
PROJECT=REPO/'fpga/custom_project/sc520-contour29-retime'
BASEPROJECT=REPO/'fpga/custom_project/sc520-contour29'
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
    assert snapshot and destination.is_relative_to(REPO/'evidence/sc520-contour29-retime/builds')
    assert not destination.exists(), 'Never overwrite a prepared or executed run'
    original_software=REPO/'evidence/sc520-contour29/software-v1.json'
    assert sha(original_software)=='890456358DECFE262EF3086843063FD4006A24340461F1333C0274096036DDC7'
    original_manifest=json.loads(original_software.read_text(encoding='utf-8-sig'))
    frozen=original_manifest['SourceFreeze']
    assert len(frozen)==53
    for row in frozen:assert sha(row['Path'])==row['SHA256'],row['Path']
    protection=original_manifest['FrozenBaselineProtection']
    assert sha(protection['Path'])==protection['SHA256']
    protected=json.loads(Path(protection['Path']).read_text(encoding='utf-8-sig'))['Files']
    assert len(protected)==3165
    for row in protected:assert sha(row['Path'])==row['SHA256'],row['Path']
    r4_snapshot=REPO/'evidence/sc520-contour29/interruption-r4-20261021-1715/run-files.json'
    assert sha(r4_snapshot)=='1DE04CEC57DEA6DF5BE300CB50F9BED9E991A2DF5984BD0B863788CBDC7497FE'
    r4_files=json.loads(r4_snapshot.read_text(encoding='utf-8-sig'))
    assert len(r4_files)==138
    for row in r4_files:assert sha(row['Path'])==row['SHA256'],row['Path']
    original_top=BASEPROJECT/'overlay/design_top_wrapper.v'
    candidate_top=PROJECT/'overlay/design_top_wrapper.v'
    assert original_top.read_bytes().count(b"16'h0290")==2
    assert candidate_top.read_bytes()==original_top.read_bytes().replace(b"16'h0290",b"16'h0291")
    destination.mkdir(parents=True,exist_ok=False)
    sources=sorted((RTL/'pixel14').glob('*.v'))+sorted((RTL/'items14').glob('*.v'))+[RTL/n for n in ('card_template_rom.v','card_result_filter.v')]
    sources += [BASEPROJECT/'overlay/pixel14_color_pipeline.v']
    sources += sorted((RTL/'color_diag').glob('*.v'))
    sources += [RTL/'display17'/name for name in ('sc520_processing_display.v','sc520_color_classify.v','sc520_logo_pipeline.v','pixel17_display_request.v')]
    sources += sorted((RTL/'audio22').glob('*.v'))+sorted((RTL/'audio22/imported').glob('*.v'))
    sources += sorted((RTL/'timing23').glob('*.v'))
    sources += sorted((REPO/'fpga/rtl/sc520-color-integration').glob('*.v'))
    sources += sorted((REPO/'fpga/rtl/sc520-shape27').glob('*.v'))
    sources += [REPO/'fpga/rtl/sc520-contour29-retime/pixel29_scene_preprocess.v'
                if p.name=='pixel29_scene_preprocess.v' else p
                for p in sorted((REPO/'fpga/rtl/sc520-contour29').glob('*.v'))]
    mapping={}
    records=[]
    if snapshot:
        for name in ('prepare-contour29-retime.py','build-contour29-retime.py','audit-contour29-reset.py','audit-timing23-reset.py','audit-shape27-reset.py'):
            p=Path(__file__).with_name(name);q=destination/'tools'/name
            q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in sources:
            q=destination/'rtl'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            mapping[p.resolve()]=q;records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in (BASEPROJECT/'overlay').glob('*'):
            if p.name=='design_top_wrapper.v':p=PROJECT/'overlay/design_top_wrapper.v'
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
    profile_path=REPO/'assets/templates/sc520-card-recognition/audio22/hardware-default.json'
    profile=__import__('json').loads(profile_path.read_text(encoding='utf-8'))
    assert profile['BitGenerationAllowed'] is False and profile['HardwareValidated'] is False
    records.append({'Path':str(profile_path),'SHA256':sha(profile_path)})
    assert not profile['TestOnly'] and profile['TRACKS']==[]
    save(destination/'profile.json',profile)
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
        if stage=='phy_1':settings=once(settings,'set end_step bitgen','set end_step opt_route')
        write(run/'settings.cfg',settings)
        flow=(oldrun/'camera_to_dsi_display.tcl').read_text(encoding='utf-8-sig')
        start=flow.index('proc bitgen_fun {} {');end=flow.index('foreach s [lrange',start)
        flow=flow[:start]+'proc bitgen_fun {} {error "D0291 forbids bitgen until new physical acceptance"}\n'+flow[end:]
        write(run/'camera_to_dsi_display.tcl',flow)
    # Include collateral IP netlists, include files and ADC/SDC inputs in hashes.
    external=set(refs)
    for base in (OLD/'user_source',OLD/'td_project/al_ip'):
        external.update(p for p in base.rglob('*') if p.is_file() and p.suffix.lower() not in ('.bit','.db','.log','.wlf'))
    for p in sorted(external):
        records.append({'Path':str(p),'SHA256':sha(p)})
    for r in records:
        if 'Snapshot' in r:r['SnapshotSHA256']=sha(r['Snapshot'])
    geometry=REPO/'assets/templates/sc520-contour29/contour29-shapes.mem'
    geometry_copies=[destination/'contour29-shapes.mem',destination/'rtl/contour29-shapes.mem',destination/'td_project/contour29-shapes.mem']
    geometry_copies += [destination/f'td_project/camera_to_dsi_display_Runs/{stage}/contour29-shapes.mem' for stage in ('syn_1','phy_1')]
    for q in geometry_copies:
        assert not q.exists()
        shutil.copyfile(geometry,q)
        records.append({'Path':str(geometry),'SHA256':sha(geometry),'Snapshot':str(q),'SnapshotSHA256':sha(q)})
    result={'CreatedAt':datetime.datetime.now().astimezone().isoformat(),'Owner':'Codex /root/contour29_reconcile D0291',
        'Candidate':'D0291','BitGenerationAllowed':False,
        'SourceProject':str(OLD),'Project':str(destination),'Snapshot':snapshot,'Files':records,
        'ManifestSources':[str(p) for p in sorted(refs)],'HardwareValidated':False,
        'GeometryROM':{'Source':str(geometry),'SHA256':sha(geometry),'Copies':[str(p) for p in geometry_copies],'Width':16,'Words':1024},
        'SelectionPolicy':'Only scene source replacement; new top differs from original overlay only in two version constants. Vendor/IP and clocks/constraints unchanged.'}
    save(destination/'inputs.json',result)
    prepared_files=[{'Path':str(p),'SHA256':sha(p),'Bytes':p.stat().st_size}
                    for p in sorted(destination.rglob('*')) if p.is_file()]
    preparation={'Candidate':'D0291','PreparedAt':datetime.datetime.now().astimezone().isoformat(),
        'Owner':'Codex /root/contour29_reconcile','TDStarted':False,'BitGenerationAllowed':False,
        'SourceCommitObserved':subprocess.check_output(['git','-C',str(REPO),'rev-parse','HEAD'],text=True).strip(),
        'OriginalBaselineSourceFreeze':frozen,
        'OriginalSoftware':{'Path':str(original_software),'SHA256':sha(original_software)},
        'FrozenBaselineProtection':protection,
        'ProtectedBaselineCount':len(protected),
        'PreservedR4Snapshot':{'Path':str(r4_snapshot),'SHA256':sha(r4_snapshot)},
        'PreservedR4FileCount':len(r4_files),
        'Program':{'Path':str(Path(__file__).resolve()),'SHA256':sha(__file__)},
        'Builder':{'Path':str(Path(__file__).with_name('build-contour29-retime.py')),'SHA256':sha(Path(__file__).with_name('build-contour29-retime.py'))},
        'PreparedFiles':prepared_files,'InputManifest':{'Path':str(destination/'inputs.json'),'SHA256':sha(destination/'inputs.json')},
        'SourceSelectionCount':len(refs),'GeometryROMCopies':len(geometry_copies),
        'Changes':['Only original scene source is replaced by independent retimed scene.',
                   'New top source only changes exactly two version literals 0290 to 0291; snapshot asset paths point into this new run.',
                   'Standalone preparer/builder are direct implementations; all five same-byte geometry ROM search copies retained.',
                   'No inherited database, native stage marker, synthesis result, route result or bit.'],
        'HardwareValidated':False}
    save(destination/'preparation.json',preparation)
    print(f'PIXEL14_PREPARED project={destination} refs={len(refs)} hashes={len(records)}')

if __name__=='__main__':
    if sys.flags.optimize:raise RuntimeError('Python -O/-OO is prohibited for this preparation pipeline')
    ap=argparse.ArgumentParser();ap.add_argument('--snapshot',type=Path);args=ap.parse_args()
    assert args.snapshot, '--snapshot must name a new isolated evidence build directory'
    make(args.snapshot,True)
