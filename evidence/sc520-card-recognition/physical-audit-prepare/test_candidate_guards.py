"""Test physical audit rejection paths using copies of actual 111 ROM bindings."""
from pathlib import Path
import copy,importlib.util,json,re
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('candidate_guard_base',ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py')
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)

def main():
    run=ROOT/'evidence/sc520-card-recognition/builds/6a50b111';phy=run/'td_project/camera_to_dsi_display_Runs/phy_1'
    syn=run/'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v';route=phy/'pixel14-phy_1-netlist.v'
    st,rt=audit.read(syn),audit.read(route)
    sm={m['Name']:m for m in audit.memories(st)};pm={m['Name']:m for m in audit.memories(rt)}
    bindings=json.loads(audit.read(HERE/'rom-bindings-111-v1.json'))['Bindings'];clocks=audit.routed_clock_buffers(rt)
    checks=[]
    def ok(name,condition):assert condition,name;checks.append(name)
    def reject(name,fn):
        try:fn()
        except AssertionError:checks.append(name);return
        raise AssertionError('Corruption accepted: '+name)
    for name in bindings:
        result=audit.routed_rom_controls(sm[name],pm[name],clocks)
        ok('actual_routed_control_'+name,result['FunctionalParametersMatched'])
    name=next(n for n in bindings if 'rotation_mode$matcher' in n);gate=sm[name];route_mem=pm[name]
    def mutate_parameter(key,value):
        x={**route_mem,'Params':{**route_mem['Params'],key:value}}
        return lambda:audit.routed_rom_controls(gate,x,clocks)
    reject('wrong_read_width_rejected',mutate_parameter('DATA_WIDTH_B','10'))
    reject('write_enable_rejected',mutate_parameter('WEBMUX','1'))
    reject('chip_select_polarity_rejected',mutate_parameter('CSB0','0'))
    reject('read_register_mode_rejected',mutate_parameter('REGMODE_B','OUTREG'))
    reject('new_unknown_functional_parameter_rejected',mutate_parameter('UNREVIEWED_MODE','1'))
    reject('readback_mode_rejected',mutate_parameter('READBACK','ENABLE'))
    def mutate_port(key,value):
        x={**route_mem,'Ports':{**route_mem['Ports'],key:value}}
        return lambda:audit.routed_rom_controls(gate,x,clocks)
    reject('wrong_clock_source_rejected',mutate_port('clkb','unrelated_clock'))
    reject('wrong_chip_select_net_rejected',mutate_port('csb',"3'b111"))
    reject('wrong_word_address_rejected',mutate_port('addrb',"14'b0"))
    reject('wrong_output_mapping_rejected',mutate_port('dob',"16'b0"))
    x={**route_mem,'Ports':dict(route_mem['Ports'])};x['Ports']['dob']=re.sub(r'open_n\d+','open_n999999',x['Ports']['dob'])
    ok('unconnected_pin_labels_may_rename',audit.routed_rom_controls(gate,x,clocks)['FunctionalParametersMatched'])
    clock=next(v for v in clocks if v==audit.net(route_mem['Ports']['clkb']))
    loop=copy.deepcopy(clocks);loop[clock]['Input']=clock
    reject('clock_alias_cycle_rejected',lambda:audit.routed_rom_controls(gate,route_mem,loop))
    over=audit.resource_report('#slice* 44101 out of 21216 207.87%\n#reg 28129\n#eram 50 out of 108\n#dsp 41 out of 40\n')
    ok('asterisk_slice_capacity_is_not_skipped',set(over['OverCapacity'])=={'slice*','dsp'})
    gate110=ROOT/'evidence/sc520-card-recognition/builds/6a50b110/td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display_gate.area'
    actual_over=audit.resource_report(audit.read(gate110))
    ok('real_110_slice_and_dsp_overflow_rejected',set(actual_over['OverCapacity'])=={'slice*','dsp'})
    actual111=audit.resource_report(audit.read(phy/'camera_to_dsi_display_phy.area'))
    ok('real_111_resource_limits_all_counted',bool({'slice','slice*'} & actual111['Available'].keys()) and not actual111['OverCapacity'])
    report={'CreatedAt':audit.now(),'Passed':len(checks),'Checks':checks,'CandidateQualified':False,'HardwareValidated':False,
            'Scope':'Audit guards only. Actual 111 remains STA-negative; corruption is in-memory and no original source/report is modified.',
            '111Resources':actual111,'110RejectedCapacity':actual_over['OverCapacity'],
            'Evidence':[audit.artifact(p) for p in [syn,route,gate110,phy/'camera_to_dsi_display_phy.area',HERE/'rom-bindings-111-v1.json']],
            'Programs':[audit.artifact(Path(__file__).resolve()),audit.artifact(ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py')]}
    output=HERE/'candidate-guard-tests-v1.json';audit.emit(output,report)
    print(json.dumps({'Passed':len(checks),'Output':str(output),'CandidateQualified':False}))
if __name__=='__main__':main()
