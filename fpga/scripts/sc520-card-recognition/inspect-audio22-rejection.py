"""Collect independent evidence for a timing-rejected T022 run, never qualify it.

Strict timing criteria remain unchanged. The original failure and native
reports remain authoritative; passing subchecks cannot override global timing.
"""
from pathlib import Path
import argparse, collections, importlib.util, json, re, traceback

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition'
spec = importlib.util.spec_from_file_location('audio22_strict', Path(__file__).with_name('audit-audio22-probe.py'))
a22 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a22)
base, obs, phys, scene = a22.base, a22.observation, a22.phys, a22.scene


def read(p):
    return json.loads(base.read(p))


def pair(run, cells, label, source, destination, clock):
    paths = phys.timing_paths(run / 'analysis' / (label + '.rpt'), cells)
    assert len(paths) == 2 and {x['Check'] for x in paths} == {'setup', 'hold'}
    for p in paths:
        assert p['SourceNet'] == source and p['DestinationNet'] == destination, p
        assert p['FromClock'] == p['ToClock'] == clock and p['SlackNs'] >= 0, p
        if p['Check'] == 'setup':
            assert p['BudgetNs'] == 2 and 0 <= p['DelayNs'] < 2, p
    return {'Name': label, 'Paths': paths}


def i2c_review(run, text, cells):
    buffers, decl = base.routed_clock_buffers(text), base.declarations(text)
    roots = []
    for m in re.finditer(r'PH1P_PHY_PLL_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);', text, re.S):
        if base.net(m[2]) == 'u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL':
            ports = dict(re.findall(r'\.(\w+)\(([^()]*)\)', m[3]))
            roots.append(base.bits(ports['clkc'], decl)[1])
    assert len(roots) == 1
    registers = []
    for name, (params, ports) in cells.items():
        q = {pin: ports[pin] for pin in ('oqa', 'oqb')
             if ports.get(pin, '').startswith(('u_uicfgcs520/u_i2c/', 'O_cam_scl'))}
        if not q and not name.startswith('u_uicfgcs520/u_i2c/'):
            continue
        if 'clk' not in ports:
            assert not q, (name, q)
            continue
        node, chain = ports['clk'], []
        while node in buffers:
            chain.append(buffers[node])
            node = buffers[node]['Input']
        assert node == roots[0], (name, node, roots[0])
        registers.append({'Cell': name, 'Q': q, 'ClockRoot': node, 'ClockChain': chain})
    assert len(registers) > 30
    records = [p for name in ('i2c-core-inbound.rpt', 'i2c-core-outbound.rpt')
               for p in obs.scl.path_records(run / 'analysis' / name)]
    assert {r['Cell'] for r in registers} <= {p['End'].rsplit('.', 1)[0] for p in records}
    assert {p['Check'] for p in records} == {'setup', 'hold', 'recovery', 'removal'}
    for p in records:
        assert p['FromClock'] == p['ToClock'] == 'pll_clk_24m' and p['SlackNs'] >= 0 and p['TargetEdge'] == 'rising', p
    assert 'u_uicfgcs520/u_i2c/scl_clk' not in base.read(run / 'td_project/camera_to_dsi_display_Runs/phy_1/route_clock_utilization.txt')
    return {'Registers': registers, 'Records': records,
            'MinimumSlackNs': {k: min(p['SlackNs'] for p in records if p['Check'] == k)
                               for k in ('setup', 'hold', 'recovery', 'removal')}}


def protected_review():
    start = read(E / 'audio22/start.json')
    for x in start['Protected'] + start['Imports']:
        assert base.sha(x['Path']) == x['SHA256'], x['Path']
    return {'Start': base.artifact(E / 'audio22/start.json'), 'ProtectedCount': len(start['Protected']), 'Imports': start['Imports']}


def software_review():
    path = E / 'audio22/software-validation-v2.json'
    report = read(path)
    assert report['Qualified'] and report['PositiveScenarios'] == 44 and report['PositiveChecks'] == 12199365
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
    assert count == 602
    return {'Software': base.artifact(path), 'RawReferencesChecked': count, 'Scenarios': 44, 'Checks': 12199365, 'Reexecuted': False}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run', type=Path)
    ap.add_argument('--bindings', required=True, type=Path)
    ap.add_argument('--coordinator-review', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    assert not args.output.exists()
    run = args.run.resolve()
    phy = run / 'td_project/camera_to_dsi_display_Runs/phy_1'
    native = read(run / 'result.json')
    assert not native['ChangedInputs'] and native['TestOnly'] and not native['BitGenerationAllowed']
    assert [(x['Stage'], x['ExitCode'], x['MarkerFresh']) for x in native['Stages']] == [('syn_1', 0, True), ('phy_1', 0, True)]
    assert not (run / 'failure.json').exists() and (phy / '.opt_route.end.f').exists()
    assert not (phy / '.bitgen.begin.f').exists() and not list(run.rglob('*.bit'))
    assert not list((ROOT / 'fpga/custom_project/sc520-audio22').rglob('*.bit'))
    assert 'set end_step opt_route' in base.read(phy / 'settings.cfg')
    assert 'proc bitgen_fun {} {error "T022 forbids bitgen"}' in base.read(phy / 'camera_to_dsi_display.tcl')
    assert 'PIXEL14_STAGE_OK phy_1' in base.read(run / 'phy_1.stdout.log')
    timing = base.read(phy / 'camera_to_dsi_display_pr.timing')
    metrics = {k: float(re.search(r'\b' + k + r':\s*(-?[0-9.]+)ns', timing)[1]) for k in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    assert metrics['SWNS'] < 0 or metrics['HWNS'] < 0 or metrics['STNS'] != 0 or metrics['HTNS'] != 0, 'Use the normal strict auditor for a passing run'
    text = base.read(phy / 'pixel14-phy_1-netlist.v')
    cells = phys.slices(text)
    checks = {}

    def collect(name, fn):
        try:
            checks[name] = {'Passed': True, 'Evidence': fn()}
        except Exception:
            checks[name] = {'Passed': False, 'Error': traceback.format_exc()}

    base.logical_roms = a22.logical_roms

    def rom_review():
        result = base.rom_audit(run, 'scene', True, read(args.bindings))
        assert len(result['ROMs']) == 39 and not result['UnreviewedAddressOrSelectMappings']
        return result

    collect('RoutedROMs', rom_review)
    collect('Inputs', lambda: base.validate_inputs(run))
    collect('ProfileAndConstraints', lambda: a22.profile_review(run))
    collect('RecoveryCopies', lambda: a22.recovery_review(run))
    collect('CoordinatorAndLegacyProtection', lambda: obs.preservation_review(args.coordinator_review))
    collect('Legacy17SynchronizersAndThreeMailboxes', lambda: scene.cdc_audit(run))

    def color_review():
        mailbox, prefix = obs.color_mailbox(run, cells)
        pairs = [obs.extra_pair(run, cells, 'color-' + s, prefix + '/' + s) for s in ('req', 'ack')]
        return {'Mailbox': mailbox, 'Synchronizers': pairs}

    collect('ColorMailboxAndTwoSynchronizers', color_review)
    collect('I2CTwoSynchronizers', lambda: [pair(run, cells, label, 'u_uicfgcs520/u_i2c/' + start,
                                               'u_uicfgcs520/u_i2c/' + end, 'pll_clk_24m')
            for label, start, end in [('i2c-reset', 'reset_pipe[0]', 'reset_pipe[1]'), ('i2c-sda', 'sda_meta', 'sda_sync')]])
    collect('I2CClockAndAllReportedPaths', lambda: i2c_review(run, text, cells))
    collect('AudioClockThreeSynchronizersAndAllReportedPaths', lambda: a22.audio_paths(run))
    collect('ProtectedFilesAndImports', protected_review)
    collect('SoftwareRawEvidence', software_review)

    def unchanged():
        baseline = E / 'builds/6a50b113'
        rows = []
        for folder, names in [('overlay', ['uii2c.v', 'uicfgcs520.v']), ('rtl', [
                'block_frame_recognizer.v', 'pixel14_rotation_matcher.v', 'pixel14_block_shape_guard.v',
                'pixel14_block_filter.v', 'card_result_filter.v', 'items14_quiz_control.v', 'items14_result_join.v']), ('', ['templates.mem'])]:
            for name in names:
                assert base.sha(run / folder / name) == base.sha(baseline / folder / name), name
                rows.append(base.artifact(run / folder / name))
        return rows

    collect('I2CClassificationAndTemplatesUnchanged', unchanged)
    area = base.read(phy / 'camera_to_dsi_display_phy.area')
    resources = base.resource_report(area)
    assert not resources['OverCapacity']
    pins = []
    for port, ball, direction in [('I_quiz_keys_n[0]', 'D5', 'INPUT'), ('I_quiz_keys_n[1]', 'A9', 'INPUT'),
                                  ('I_quiz_keys_n[2]', 'B9', 'INPUT'), ('I_quiz_keys_n[3]', 'C7', 'INPUT'),
                                  ('O_audio_tx', 'C18', 'OUTPUT'), ('I_audio_rx', 'D15', 'INPUT'), ('I_audio_busy', 'E12', 'INPUT')]:
        m = re.search(re.escape(port) + r'\s+' + direction + r'\s+(\S+)\s+(\S+)', area)
        assert m and m.groups() == (ball, 'LVCMOS33'), port
        pins.append({'Port': port, 'Ball': ball, 'TestCandidateOnly': 'audio' in port})
    rows = obs.scl.path_records(phy / 'camera_to_dsi_display_pr.timing')
    bad = [x for x in rows if x['SlackNs'] < 0]
    groups = []
    for clock, kind in sorted({(x['FromClock'], x['Check']) for x in bad}):
        paths = sorted([x for x in bad if x['FromClock'] == clock and x['Check'] == kind], key=lambda p: p['SlackNs'])
        groups.append({'Clock': clock, 'Check': kind, 'ReportedFailingPaths': paths,
                       'ReportIsEndpointLimited': True})
    old = read(E / 'delivery-0117/manifest.json')['Resources']['Used']
    delta = {k: resources['Used'][k] - old[k] for k in ('lut6', 'reg', 'slice', 'eram', 'dsp')}
    report = {'At': base.now(), 'Owner': '01a142a0-2945-7823-b9c2-868aa816a6f6 /root',
              'Status': 'REJECTED: final global setup/recovery timing violations', 'Run': str(run),
              'ProbeQualified': False, 'CandidateQualified': False, 'Downloadable': False,
              'BitGenerationAllowed': False, 'BitFilesFound': [], 'HardwareValidated': False,
              'FullSystemTimingSignoff': False, 'TimingNs': metrics, 'Resources': resources,
              'ResourceDeltaFrom0117': delta, 'KeyAndTestIO': pins, 'IndependentChecks': checks,
              'AllNonTimingChecksPassed': all(c['Passed'] for c in checks.values()),
              'GlobalReportedPaths': rows, 'FailingPathGroups': groups,
              'NativeResult': base.artifact(run / 'result.json'), 'NativeStages': base.artifact(run / 'stages.json'),
              'StrictAuditAttempt': base.artifact(E / 'audio22/audit-attempt-1.json'),
              'StrictAuditor': base.artifact(Path(a22.__file__)), 'Program': base.artifact(__file__),
              'InitialAuditorSnapshot': base.artifact(E / 'audio22/audit-source-v1/audit-audio22-probe.py'),
              'PhysicalReports': [base.artifact(phy / p) for p in ['camera_to_dsi_display_pr.timing', 'final_timing.rpt',
                  'camera_to_dsi_display_phy.area', 'pixel14-phy_1-netlist.v', 'camera_to_dsi_display_pr.db']],
              'Limits': 'Independent passing checks do not waive global violations. No clock/exception change, bitgen, board qualification, physical track mapping, connector or external audio timing approval.'}
    base.emit(args.output, report)
    print(json.dumps({'Status': report['Status'], 'Timing': metrics, 'CheckStatus': {k: v['Passed'] for k, v in checks.items()}, 'ResourceDelta': delta}))


if __name__ == '__main__':
    main()
