"""Audit the new T023 route, retaining failed subchecks and native reports."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import traceback

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


inherited = load('timing23_support', Path(__file__).with_name('inspect-audio22-rejection.py'))
a22, base, obs, phys, scene = inherited.a22, inherited.base, inherited.obs, inherited.phys, inherited.scene


def read(path):
    return json.loads(base.read(path))


def address_adapter(run, proof_dir):
    """Adapt only the three locally proven aliases in this exact routed ROM."""
    syn = run / 'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    route = run / 'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v'
    prefix = 'u_p14_pipeline/scene_mode$scene/'
    pairs = [{'Bit': bit, 'Canonical': prefix + f'card_index[{bit}]',
              'Routed': prefix + f'card_index[{bit}]' + suffix}
             for bit, suffix in ((5, '_dup_4'), (6, '_dup_6'), (8, '_dup_3'))]
    expected = {
        'normal': (0, {'errors': 0, 'checks': 475190, 'rows': 16384, 'injected': 0, 'done': 1}),
        'negative': (1, {'errors': 1, 'checks': 475191, 'rows': 16384, 'injected': 1, 'done': 1}),
        'watchdog': (2, {'errors': 0, 'checks': 1449, 'rows': 49, 'injected': 0, 'done': 0}),
    }
    proof_parser = load('timing23_address_cells', Path(__file__).with_name('prove-timing23-address.py'))
    raw_by_primitive = {
        'AL_MAP_SEQ_GSR': proof_parser.cells(base.read(syn), 'AL_MAP_SEQ_GSR'),
        'AL_MAP_LUT2': proof_parser.cells(base.read(syn), 'AL_MAP_LUT2'),
        'PH1P_PHY_LSLICE': proof_parser.cells(base.read(route), 'PH1P_PHY_LSLICE'),
        'PH1P_PHY_SCLK_V2': proof_parser.cells(base.read(route), 'PH1P_PHY_SCLK_V2'),
    }
    qualified = []
    first = None
    for mode, (exit_code, summary) in expected.items():
        path = proof_dir / mode / 'proof.json'
        proof = read(path)
        assert proof['Verified'] and proof['Mode'] == mode
        assert proof['NativeExit'] == exit_code and proof['Summary'] == summary
        assert proof['Pairs'] == pairs and len(proof['LeafSignals']) == 11
        assert len(proof['ExactCells']) == 10
        for item in proof['Inputs'] + proof['Artifacts']:
            assert base.sha(item['Path']) == item['SHA256'], item['Path']
            assert Path(item['Path']).stat().st_size == item['Bytes'], item['Path']
            if 'Snapshot' in item:
                copy = item['Snapshot']
                assert base.sha(copy['Path']) == copy['SHA256'] == item['SHA256']
                assert Path(copy['Path']).stat().st_size == copy['Bytes'] == item['Bytes']
        assert [Path(x['Path']).resolve() for x in proof['Inputs'][:3]] == [
            syn.resolve(), route.resolve(), Path(proof_parser.__file__).resolve()]
        for cell in proof['ExactCells']:
            actual = raw_by_primitive[cell['Primitive']][cell['Name']]
            assert cell == {k: v for k, v in actual.items() if k != 'Raw'}, cell['Name']
        if first is None:
            first = proof
        else:
            for key in ('LeafSignals', 'Pairs', 'ExactCells', 'ResetPrecondition', 'Scope'):
                assert proof[key] == first[key], (mode, key)
        qualified.append({'Mode': mode, 'Proof': base.artifact(path),
                          'NativeExit': exit_code, 'Summary': summary})
    original = base.memories
    route_text = base.read(route)
    route_text_digest = hashlib.sha256(route_text.encode()).hexdigest()
    aliases = {p['Routed']: p['Canonical'] for p in pairs}
    adapted = []

    def parsed_memories(source_text):
        result = original(source_text)
        if hashlib.sha256(source_text.encode()).hexdigest() != route_text_digest:
            return result
        selected = [m for m in result
                    if m['Name'] == 'u_p14_pipeline/shape_mode$shape_guard/templates/ramread0_syn_23']
        assert len(selected) == 1
        memory = selected[0]
        for port in ('addra', 'addrb'):
            before = base.bits(memory['Ports'][port], memory['Declarations'])
            assert len(before) == 14
            assert all(before.count(signal) == 1 for signal in aliases)
            after = [aliases.get(signal, signal) for signal in before]
            memory['Ports'][port] = '{' + ','.join(
                "1'b" + signal if signal in ('0', '1') else '\\' + signal + ' '
                for signal in reversed(after)) + '}'
            assert base.bits(memory['Ports'][port], memory['Declarations']) == after
            adapted.append({'ROM': memory['Name'], 'Port': port, 'Before': before, 'After': after})
        return result

    base.memories = parsed_memories
    return original, adapted, {
        'ProofRuns': qualified, 'SynNetlist': base.artifact(syn),
        'RoutedNetlist': base.artifact(route), 'Pairs': pairs,
        'ResetPrecondition': first['ResetPrecondition'], 'Scope': first['Scope'],
        'WholeNetlistFormalEquivalence': False,
    }


def reset_outbound(path, cells, expected_net):
    records = obs.scl.path_records(path)
    blocks = re.split(r'(?m)^Slack\s*:', base.read(path))[1:]
    assert len(records) == len(blocks) and records
    for row, block in zip(records, blocks):
        match = re.search(r'(?m)^clk2q[^\n]*\bpin:\s*(\S+\.oq[ab])\s*$', block)
        assert match, (path, row)
        source_q = base.net(match[1])
        source_cell, pin = source_q.rsplit('.', 1)
        assert row['Begin'] == source_cell + '.clk', row
        source_net = cells[source_cell][1][pin]
        net_match = re.search(
            r'(?m)^net \(fo=(\d+)\)\s+(-?[0-9.]+)[^\n]*\bnet:\s*(\S+),',
            block[match.end():])
        assert net_match and base.net(net_match[3]) == source_net, (path, source_q)
        row.update(SourceQ=source_q, SourceNet=source_net,
                   SourceNetFanout=int(net_match[1]), SourceNetDelayNs=float(net_match[2]),
                   OwnResetQ=source_net == expected_net)
    own = [p for p in records if p['OwnResetQ']]
    copacked = [p for p in records if not p['OwnResetQ']]
    assert own, ('No paths from the intended reset Q', path, expected_net)
    fanouts = {p['SourceNetFanout'] for p in own}
    assert len(fanouts) == 1, (expected_net, fanouts)

    def minimum(paths):
        return {k: min(p['SlackNs'] for p in paths if p['Check'] == k)
                for k in {p['Check'] for p in paths}}

    return {'Reset': expected_net, 'Report': base.artifact(path),
            'Paths': records, 'OwnQPaths': own, 'CoPackedQPaths': copacked,
            'MinimumSlackNs': minimum(own), 'CombinedReportMinimumSlackNs': minimum(records),
            'PhysicalSourceNetFanout': fanouts.pop(),
            'PhysicalSourceNetDelayNs': {
                'Min': min(p['SourceNetDelayNs'] for p in own),
                'Max': max(p['SourceNetDelayNs'] for p in own)},
            'SelectionNote': 'TD get_regs selects an LSLICE. Both FF outputs may be reported; '
                             'each clk2q pin is resolved through the actual physical netlist.'}


def profiles_and_constraints(run):
    hardware_path = ROOT / 'assets/templates/sc520-card-recognition/audio22/hardware-default.json'
    test_path = hardware_path.with_name('offline-test.json')
    hardware, test, actual = [read(p) for p in (hardware_path, test_path, run / 'profile.json')]
    assert not hardware['TestOnly'] and hardware['TRACKS'] == []
    assert all(hardware[k] == 0 and test[k] == 1 for k in ('MAP_VERIFIED', 'STATUS_VERIFIED', 'MODE_VERIFIED'))
    assert test == actual and test['TestOnly'] and test['TRACKS'] == list(range(0x1201, 0x1224))
    assert all(not p['BitGenerationAllowed'] and not p['HardwareValidated'] for p in (hardware, test, actual))
    source = ROOT / 'fpga/custom_project/sc520-timing23/overlay/design_top_wrapper.v'
    text = base.read(source)
    assert 'AUDIO_MAP_VERIFIED=0,AUDIO_STATUS_VERIFIED=0,AUDIO_MODE_VERIFIED=0' in text
    assert "AUDIO_TRACKS=560'd0" in text
    expected = text.replace('AUDIO_MAP_VERIFIED=0,AUDIO_STATUS_VERIFIED=0,AUDIO_MODE_VERIFIED=0',
                            'AUDIO_MAP_VERIFIED=1,AUDIO_STATUS_VERIFIED=1,AUDIO_MODE_VERIFIED=1')
    expected = expected.replace("AUDIO_TRACKS=560'd0", "AUDIO_TRACKS=560'h" +
                                ''.join(f'{x:04X}' for x in reversed(test['TRACKS'])))
    for item in read(run / 'inputs.json')['Files']:
        if item.get('Snapshot') and Path(item['Snapshot']).name in (
                'templates.mem', 'anlogic_logo_index.mem', 'anlogic_logo_palette.mem'):
            expected = expected.replace(Path(item['Path']).as_posix(), Path(item['Snapshot']).as_posix())
    assert '// TEST ONLY SYNTHETIC MAPPING. NO BITGEN OR HARDWARE QUALIFICATION.\n' + expected == base.read(run / 'overlay/design_top_wrapper.v')
    previous = base.read(ROOT / 'fpga/custom_project/sc520-audio22/overlay/pixel14.sdc')
    current = base.read(run / 'overlay/pixel14.sdc')
    assert current.startswith(previous), 'Original clocks or timing exceptions changed'
    commands = [s.strip() for s in current[len(previous):].splitlines()
                if s.strip() and not s.lstrip().startswith('#')]
    branches = ['capture_reset[1]'] + [f'capture_release[{i}]' for i in range(9)]
    exact = ['set_max_delay -from [get_regs {u_p14_pipeline/capture_reset[0]}] '
             '-to [get_regs {u_p14_pipeline/' + q + '}] 2.000' for q in branches]
    assert commands == exact, commands
    return {'Profiles': [base.artifact(p) for p in (hardware_path, test_path, run / 'profile.json')],
            'FormalVerifiedFieldsZero': True, 'FormalTracksEmpty': True,
            'SyntheticProfileTransformationExact': True, 'OriginalConstraintsPreserved': True,
            'ExactResetConstraints': commands}


def software_review():
    path = E / 'timing23/software-validation-v1.json'
    report = read(path)
    assert report['Qualified'] and report['PositiveScenarios'] == 51 and report['PositiveChecks'] == 28685263
    count = 0
    for row in report['Runs']:
        assert base.sha(row['Path']) == row['SHA256']
        run = read(row['Path'])
        assert run['Qualified'] and run['Summary'] == row['Summary']
        assert run['NativeExitCode'] == {'normal': 0, 'negative': 1, 'watchdog': 2}[row['Mode']]
        for x in run['Inputs']:
            assert base.sha(x['path']) == base.sha(x['snapshot']) == x['sha256_before'].upper() == x['sha256_after'].upper() == x['snapshot_sha256'].upper()
            count += 1
        for x in run['Outputs']:
            assert base.sha(x['path']) == x['sha256'].upper()
            count += 1
    assert count == report['CurrentReferencesChecked'] == 872
    for frame in report['FullFrames']:
        for key in ('ActualPPM', 'Golden', 'Preview'):
            assert base.sha(frame[key]['Path']) == frame[key]['SHA256']
    return {'Software': base.artifact(path), 'ReferencesChecked': count,
            'Scenarios': 51, 'Checks': 28685263, 'Reexecuted': False}


def reset_review(run, cells):
    synthesis = read(run / 'reset-synthesis.json')
    assert synthesis['Qualified'] and synthesis['SecondStageCount'] == 10
    assert base.sha(synthesis['Netlist']['Path']) == synthesis['Netlist']['SHA256']
    names = ['u_p14_pipeline/capture_reset[1]'] + [f'u_p14_pipeline/capture_release[{i}]' for i in range(9)]
    first_name = 'u_p14_pipeline/capture_reset[0]'
    q_map = {}
    for name, (params, ports) in cells.items():
        for half in ('a', 'b'):
            q = ports.get('oq' + half)
            if q in names + [first_name]:
                assert q not in q_map, ('Multiple physical reset drivers', q)
                q_map[q] = {'Cell': name, 'Half': half, 'Parameters': params, 'Ports': ports}
    assert set(q_map) == set(names + [first_name]), ('Missing physical reset copies', set(names + [first_name]) - set(q_map))
    routed_text = base.read(run / 'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v')
    clock_buffers = base.routed_clock_buffers(routed_text)

    def clock_root(signal):
        chain = []
        while signal in clock_buffers:
            chain.append(clock_buffers[signal])
            signal = clock_buffers[signal]['Input']
        return signal, chain

    first_clock_root, first_clock_chain = clock_root(q_map[first_name]['Ports']['clk'])
    reset_parser = load('timing23_gate_roles', Path(__file__).with_name('audit-timing23-reset.py'))
    gates = reset_parser.gate_cells(base.read(synthesis['Netlist']['Path']))
    loads = {q: [] for q in names}
    for name, cell in gates.items():
        primitive = cell['Primitive']
        assert primitive == 'AL_MAP_SEQ_GSR' or re.fullmatch(r'AL_MAP_LUT[1-6]', primitive), primitive
        outputs = {'q'} if primitive == 'AL_MAP_SEQ_GSR' else {'o'}
        for pin, net in cell['Ports'].items():
            if pin not in outputs and net in loads:
                loads[net].append({'Cell': name, 'Pin': pin, 'Primitive': primitive})
    pairs, outbound, timing_failures = [], [], []
    for i, q in enumerate(names):
        paths = phys.timing_paths(run / 'analysis' / f'reset23-{i}.rpt', cells)
        assert len(paths) == 2 and {p['Check'] for p in paths} == {'setup', 'hold'}
        for p in paths:
            assert p['SourceNet'] == first_name and p['DestinationNet'] == q, p
            assert p['FromClock'] == p['ToClock'] == 'MIPI_RX_BYTE_CLK', p
            if p['SlackNs'] < 0:
                timing_failures.append({'Reset': q, 'Kind': 'first-to-second', 'Path': p})
            if p['Check'] == 'setup':
                assert p['BudgetNs'] == 2, p
                if not 0 <= p['DelayNs'] < 2:
                    timing_failures.append({'Reset': q, 'Kind': 'first-to-second-delay', 'Path': p})
        destination = q_map[q]
        half = destination['Half']
        root, chain = clock_root(destination['Ports']['clk'])
        assert root == first_clock_root, (q, root, first_clock_root)
        destination['ClockRoot'] = root
        destination['ClockBuffers'] = chain
        assert destination['Ports']['asr'] == q_map[first_name]['Ports']['asr']
        params = destination['Parameters']
        assert params['ASRMUX'] == 'INV' and params['REG' + half.upper() + '_REGSET_ASYNC'] == 'RESET', (q, params)
        assert params['CLKMUX'] == 'SIG' and params['LATCHMODE'] == 'DFF', (q, params)
        assert params['CE' + half.upper() + 'MUX'] == '1', (q, params)
        classified = reset_outbound(run / 'analysis' / f'reset23-{i}-outbound.rpt', cells, q)
        records = classified['Paths']
        assert records and all(p['FromClock'] == p['ToClock'] == 'MIPI_RX_BYTE_CLK' for p in records)
        timing_failures.extend({'Reset': q, 'Kind': 'outbound', 'Path': p}
                               for p in records if p['SlackNs'] < 0)
        outbound.append(classified)
        pairs.append({'Reset': q, 'PhysicalDriver': destination, 'Paths': paths,
                      'PreciseSynthesisFanoutPins': len(loads[q]), 'PreciseSynthesisLoads': loads[q]})
    return {'CheckPassed': not timing_failures, 'SynthesisAudit': base.artifact(run / 'reset-synthesis.json'),
            'FirstPhysicalStage': q_map[first_name], 'ClockRoot': first_clock_root,
            'FirstClockBuffers': first_clock_chain, 'SecondStages': pairs,
            'AdditionalSecondStages': 9, 'AuditedResetPairs': 10, 'OutboundPaths': outbound,
            'TimingFailures': timing_failures}


def io_review(run):
    area = base.read(run / 'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_phy.area')
    rows = []
    for port, ball, direction in [('I_quiz_keys_n[0]', 'D5', 'INPUT'), ('I_quiz_keys_n[1]', 'A9', 'INPUT'),
                                  ('I_quiz_keys_n[2]', 'B9', 'INPUT'), ('I_quiz_keys_n[3]', 'C7', 'INPUT'),
                                  ('O_audio_tx', 'C18', 'OUTPUT'), ('I_audio_rx', 'D15', 'INPUT'),
                                  ('I_audio_busy', 'E12', 'INPUT')]:
        m = re.search(re.escape(port) + r'\s+' + direction + r'\s+(\S+)\s+(\S+)', area)
        assert m and m.groups() == (ball, 'LVCMOS33'), port
        if port.startswith('I_quiz'):
            line = next(s for s in area.splitlines() if port in s)
            assert 'PULLUP' in line, line
        rows.append({'Port': port, 'Ball': ball, 'Direction': direction, 'OfflineTestOnly': 'audio' in port})
    original = ROOT / 'fpga/custom_project/sc520-audio22/overlay/pin.adc'
    normalization = exact_line_endings(original, run / 'overlay/pin.adc')
    return {'IO': rows, 'ADCBaseline': base.artifact(original), 'ADCExactTransformation': normalization}


def exact_line_endings(original, current):
    before, after = Path(original).read_bytes(), Path(current).read_bytes()
    if before == after:
        transformation = 'byte-identical'
    else:
        # start-timing23 uses Windows text writing for the three copied overlays.
        # Permit only this observed exact conversion; no stripping, ignored
        # whitespace, comment removal or any HDL/ADC token substitutions.
        assert b'\r' not in before and after == before.replace(b'\n', b'\r\n'), (original, current)
        transformation = 'exact LF -> CRLF, every other byte preserved'
    return {'Original': base.artifact(original), 'Current': base.artifact(current),
            'Transformation': transformation, 'SourceLFCount': before.count(b'\n')}


def native_log_review(run):
    paths = [run / (stage + suffix) for stage in ('syn_1', 'phy_1')
             for suffix in ('.stdout.log', '.stderr.log')]
    text = '\n'.join(base.read(p) for p in paths)
    errors = [s for s in text.splitlines() if re.search(r'\bERROR:|unknown module|black.?box', s, re.I)]
    assert not errors, errors
    for stage in ('syn_1', 'phy_1'):
        assert 'PIXEL14_STAGE_OK ' + stage in base.read(run / (stage + '.stdout.log'))
    started = read(run / 'started.json')
    assert base.sha(started['Tool']) == started['ToolSHA256']
    assert 'Tang Dynasty v6.2.168116' in base.read(
        run / 'td_project/camera_to_dsi_display_Runs/phy_1/final_timing.rpt')
    return {'Logs': [base.artifact(p) for p in paths], 'Tool': base.artifact(started['Tool']),
            'CriticalWarnings': [s for s in text.splitlines() if 'CRITICAL-WARNING' in s],
            'NativeErrors': []}


def unchanged(run):
    baseline = E / 'builds/6a50b113'
    rows = []
    for folder, names in [('overlay', ['uii2c.v', 'uicfgcs520.v']), ('rtl', [
            'block_frame_recognizer.v', 'pixel14_rotation_matcher.v', 'pixel14_block_shape_guard.v',
            'pixel14_block_filter.v', 'card_result_filter.v', 'items14_quiz_control.v',
            'items14_result_join.v']), ('', ['templates.mem'])]:
        for name in names:
            if folder == 'overlay':
                rows.append(exact_line_endings(baseline / folder / name, run / folder / name))
            else:
                assert base.sha(run / folder / name) == base.sha(baseline / folder / name), name
                rows.append(base.artifact(run / folder / name))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run', type=Path)
    ap.add_argument('--bindings', type=Path, required=True)
    ap.add_argument('--address-proof-dir', type=Path, required=True)
    ap.add_argument('--coordinator-review', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    assert not args.output.exists(), 'Preserve earlier audit attempts'
    run = args.run.resolve()
    phy = run / 'td_project/camera_to_dsi_display_Runs/phy_1'
    native = read(run / 'result.json')
    assert not native['ChangedInputs'] and native['TestOnly'] and not native['BitGenerationAllowed']
    assert [(x['Stage'], x['ExitCode'], x['MarkerFresh']) for x in native['Stages']] == [('syn_1', 0, True), ('phy_1', 0, True)]
    assert not (run / 'failure.json').exists() and (phy / '.opt_route.end.f').exists()
    assert not (phy / '.bitgen.begin.f').exists() and not list(run.rglob('*.bit'))
    assert not list((ROOT / 'fpga/custom_project/sc520-timing23').rglob('*.bit'))
    assert 'set end_step opt_route' in base.read(phy / 'settings.cfg')
    assert 'proc bitgen_fun {} {error "T023 forbids bitgen"}' in base.read(phy / 'camera_to_dsi_display.tcl')
    assert 'PIXEL14_STAGE_OK phy_1' in base.read(run / 'phy_1.stdout.log')
    text = base.read(phy / 'pixel14-phy_1-netlist.v')
    cells = phys.slices(text)
    checks = {}

    def collect(name, fn):
        try:
            evidence = fn()
            checks[name] = {'Passed': evidence.get('CheckPassed', True) if isinstance(evidence, dict) else True,
                            'Evidence': evidence}
        except Exception:
            checks[name] = {'Passed': False, 'Error': traceback.format_exc()}

    base.logical_roms = a22.logical_roms

    def rom_review():
        original, adapted, alias = address_adapter(run, args.address_proof_dir)
        try:
            r = base.rom_audit(run, 'scene', True, read(args.bindings))
        finally:
            base.memories = original
        assert len(adapted) == 2
        alias['InMemoryLogicalAddressBindings'] = adapted
        r['ProvenAddressAdapter'] = alias
        assert len(r['ROMs']) == 39 and not r['UnreviewedAddressOrSelectMappings']
        return r

    collect('Routed39ROMs', rom_review)
    collect('Inputs', lambda: base.validate_inputs(run))
    collect('ProfilesAndExactConstraints', lambda: profiles_and_constraints(run))
    collect('CoordinatorAndLegacyProtection', lambda: obs.preservation_review(args.coordinator_review))
    collect('Legacy17SynchronizersAndThreeMailboxes', lambda: scene.cdc_audit(run))

    def color():
        mailbox, prefix = obs.color_mailbox(run, cells)
        return {'Mailbox': mailbox, 'Synchronizers': [
            obs.extra_pair(run, cells, 'color-' + s, prefix + '/' + s) for s in ('req', 'ack')]}

    collect('ColorMailboxAndTwoSynchronizers', color)
    collect('I2CTwoSynchronizers', lambda: [
        inherited.pair(run, cells, label, 'u_uicfgcs520/u_i2c/' + start,
                       'u_uicfgcs520/u_i2c/' + end, 'pll_clk_24m') for label, start, end in
        [('i2c-reset', 'reset_pipe[0]', 'reset_pipe[1]'), ('i2c-sda', 'sda_meta', 'sda_sync')]])
    collect('I2CClockAndAllReportedPaths', lambda: inherited.i2c_review(run, text, cells))
    collect('AudioClockThreeSynchronizersAndAllReportedPaths', lambda: a22.audio_paths(run))
    collect('TenResetBranchesAndOutboundTiming', lambda: reset_review(run, cells))
    collect('ProtectedFilesAndImports', inherited.protected_review)
    collect('CurrentSoftwareRawEvidence', software_review)
    collect('I2CClassificationAndTemplatesUnchanged', lambda: unchanged(run))
    collect('FourKeysAndTestIO', lambda: io_review(run))
    collect('NativeLogsAndTool', lambda: native_log_review(run))
    timing = base.read(phy / 'camera_to_dsi_display_pr.timing')
    metrics = {k: float(re.search(r'\b' + k + r':\s*(-?[0-9.]+)ns', timing)[1])
               for k in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    rows = obs.scl.path_records(phy / 'camera_to_dsi_display_pr.timing')
    kinds = {p['Check'] for p in rows}
    # The global report is endpoint-limited and may omit a positive class.
    # Retain its aggregate WNS/TNS gate, and require original-clock reset,
    # I2C and audio reports to provide explicit witnesses for all four classes.
    class_reports = [run / 'analysis' / f'reset23-{i}-outbound.rpt' for i in range(10)]
    class_reports += [run / 'analysis' / name for name in (
        'i2c-core-inbound.rpt', 'i2c-core-outbound.rpt', 'audio-inbound.rpt', 'audio-outbound.rpt')]
    witnessed_kinds = kinds | {p['Check'] for path in class_reports for p in obs.scl.path_records(path)}
    assert witnessed_kinds == {'setup', 'hold', 'recovery', 'removal'}, witnessed_kinds
    bad = [p for p in rows if p['SlackNs'] < 0]
    global_ok = metrics['SWNS'] >= 0 and metrics['HWNS'] >= 0 and metrics['STNS'] == metrics['HTNS'] == 0 and not bad
    resources = base.resource_report(base.read(phy / 'camera_to_dsi_display_phy.area'))
    resource_ok = not resources['OverCapacity'] and resources['Used']['slice'] <= 21216 and resources['Used']['eram'] <= 108
    passed = global_ok and resource_ok and all(x['Passed'] for x in checks.values())
    report = {'At': base.now(), 'Owner': '01a144c7-e802-7272-a29d-a8159f5ec84b /root T023',
              'Run': str(run), 'Status': 'OFFLINE PROBE PASSED' if passed else 'REJECTED',
              'ProbeQualified': passed, 'GlobalTimingPassed': global_ok, 'ResourcesPassed': resource_ok,
              'IndependentChecks': checks, 'AllIndependentChecksPassed': all(x['Passed'] for x in checks.values()),
              'TimingNs': metrics, 'Resources': resources, 'GlobalReportedPaths': rows,
              'FailingGlobalPaths': bad, 'GlobalReportEndpointLimited': True,
              'GlobalSampleClasses': sorted(kinds), 'ExplicitTimingClasses': sorted(witnessed_kinds),
              'TimingClassReports': [base.artifact(p) for p in class_reports],
              'OriginalSynchronizerPairs': 24, 'AdditionalResetPairs': 10, 'AuditedPairsIfAllChecksPass': 34,
              'NativeResult': base.artifact(run / 'result.json'), 'NativeStages': base.artifact(run / 'stages.json'),
              'PhysicalReports': [base.artifact(phy / p) for p in (
                  'camera_to_dsi_display_pr.timing', 'final_timing.rpt', 'camera_to_dsi_display_phy.area',
                  'pixel14-phy_1-netlist.v', 'camera_to_dsi_display_pr.db')],
              'Programs': [base.artifact(p) for p in (
                  Path(__file__), Path(inherited.__file__), Path(a22.__file__), Path(base.__file__))],
              'CandidateQualified': False, 'Downloadable': False, 'BitGenerationAllowed': False,
              'HardwareValidated': False, 'FullSystemTimingSignoff': False,
              'Limits': 'Synthetic-profile offline probe only. All four timing classes and both TNS must pass. '
                        'Partial checks cannot override failures. No bitgen, board, connector, voltage, external audio, '
                        'media mapping, BUSY, optical correction or MTBF qualification.'}
    base.emit(args.output, report)
    print(json.dumps({'Status': report['Status'], 'Timing': metrics,
                      'Checks': {k: v['Passed'] for k, v in checks.items()}}))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
