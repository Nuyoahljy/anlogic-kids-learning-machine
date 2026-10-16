"""Prove current rotation, shape, font and Logo ROM content and selection."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, re

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / 'evidence/sc520-card-recognition'
LEGACY = ROOT / 'fpga/custom_project/sc520-pixel14/tools'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load('display17_rom_decoder', LEGACY / 'audit-scene-build.py')
derive = load('display17_cell_parser', EVIDENCE / 'physical-audit-prepare/derive_scene_rom_bindings_v3.py')


def rotation_proof(run, memories, graph, seq, slices, evaluate):
    prefix = 'u_p14_pipeline/rotation_mode$matcher/'
    bankroms = [m for m in memories if m['Name'].startswith(prefix + 'ramread0_')]
    assert len(bankroms) == 25
    expected = [int(x, 16) for x in base.read(run / 'templates.mem').split()]
    assert len(expected) == 102400
    rows, bankinfo, proofs = {}, [], []
    rtl = base.read(run / 'rtl/pixel14_rotation_matcher.v')
    assert 'mask_address==399 ? 0 : mask_address+1' in rtl and 'rom_address<=rom_address+1' in rtl
    assert all((word % 400) & 15 == word & 15 for word in range(102400))
    for memory in bankroms:
        assert memory['Params']['DATA_WIDTH_B'] == '5'
        words = base.init_decode(memory['Values'], 5)
        candidates = [b for b in range(25) if words == expected[4096 * b:4096 * (b + 1)]]
        assert len(candidates) == 1, (memory['Name'], candidates)
        bank = candidates[0]
        outputs = base.port_bits(memory)
        addresses = base.word_address_bits(memory)
        assert addresses == [prefix + f'mask_address[{i}]' for i in range(4)] + [prefix + f'rom_address[{i}]' for i in range(4, 12)]
        for group in range(32):
            for scan in (0, 1):
                env = {prefix + f'rom_address[{i}]': (group >> (i - 12)) & 1 for i in range(12, 17)}
                env[prefix + 'state_reg_syn_1[3]'] = scan
                for port in ('a', 'b'):
                    selected = 1
                    for bit, signal in enumerate(base.bits(memory['Ports']['cs' + port], memory['Declarations'])):
                        mode = memory['Params']['CS' + port.upper() + str(bit)]
                        selected &= int(mode) if mode in ('0', '1') else evaluate(signal, env.copy()) ^ (mode == 'INV')
                    assert selected == int(scan and group == bank), (memory['Name'], port, group, scan)
        rows[memory['Name']] = {'Kind': 'rotation', 'Port': 'b', 'LogicalBase': bank * 4096,
                               'LogicalOutputBits': {str(i): i for i in range(5)}, 'OutputPinsLSB': outputs,
                               'WordAddressPinsLSB': addresses, 'AddressAndSelectReviewed': True}
        bankinfo.append({'Bank': bank, 'Instance': memory['Name'], 'OutputPinsLSB': outputs})
    assert sorted(x['Bank'] for x in bankinfo) == list(range(25))
    for i in range(5):
        target = prefix + f'rom_address[12]_syn_55[{i}]'
        matches = [(name, p, q) for name, (p, q) in seq.items() if q.get('q') == target]
        assert len(matches) == 1, (target, matches)
        name, params, ports = matches[0]
        assert params['CEMUX'] == '1' and params['SRMUX'] == '0'
        for address in (0, 1):
            for scan in (0, 1):
                for old in (0, 1):
                    env = {prefix + f'rom_address[{12 + i}]': address, prefix + 'state_reg_syn_1[3]': scan, target: old}
                    assert evaluate(ports['d'], env) == (address if scan else old)
        proofs.append({'RegisteredSelect': target, 'Cell': name, 'SourceBit': 12 + i, 'TruthRows': 8})
    nodes, unique, cache = {}, {}, {}

    def mk(var, lo, hi):
        if lo == hi:
            return lo
        key = (var, lo, hi)
        if key not in unique:
            unique[key] = len(nodes) + 2
            nodes[unique[key]] = key
        return unique[key]

    def ite(c, t, e):
        if c == 1:
            return t
        if c == 0:
            return e
        if t == e:
            return t
        key = (c, t, e)
        if key in cache:
            return cache[key]
        top = min(nodes[x][0] for x in key if x > 1)

        def cof(x, side):
            return nodes[x][1 + side] if x > 1 and nodes[x][0] == top else x

        result = mk(top, ite(cof(c, 0), cof(t, 0), cof(e, 0)), ite(cof(c, 1), cof(t, 1), cof(e, 1)))
        cache[key] = result
        return result

    def lut_bdd(init, inputs):
        if not inputs:
            return init & 1
        half = 1 << (len(inputs) - 1)
        return ite(inputs[-1], lut_bdd(init >> half, inputs[:-1]), lut_bdd(init & ((1 << half) - 1), inputs[:-1]))

    def eval_bdd(signal, env):
        if signal in env:
            return env[signal]
        if signal in ('0', '1', "1'b0", "1'b1"):
            return int(signal[-1])
        assert signal in graph, ('Unresolved BDD input', signal)
        init, inputs = graph[signal]
        value = lut_bdd(init, [eval_bdd(x, env) for x in inputs])
        env[signal] = value
        return value

    bdd_proofs = []
    for col in range(5):
        candidates = [(name, p, q) for name, (p, q) in slices.items()
                      if q.get('imf') == prefix + f'distance[{col}][0]' and q.get('imb') == prefix + 'mask_q']
        assert len(candidates) == 1, (col, candidates)
        name, params, ports = candidates[0]
        assert ports['ia'] in [prefix + f'rom_address[12]_syn_55[{i}]' for i in range(5)]
        assert params['LUT5B_SD2'] == 'IMB' and params['LUT5A_SD1'] == 'IMF'
        assert params['INIT_LUT5A'] == 0xffff0000 and params['FCIMUX'] == '0'
        for bank in range(25):
            env = {prefix + f'rom_address[12]_syn_55[{i}]': (bank >> i) & 1 for i in range(5)}
            for row in bankinfo:
                for bit, signal in enumerate(row['OutputPinsLSB']):
                    env[signal] = mk(row['Bank'] * 5 + bit, 0, 1)
            mask_var, unused_var = mk(125, 0, 1), mk(126, 0, 1)
            output = lut_bdd(params['INIT_LUT5B'], [eval_bdd(ports['ia'], env), unused_var,
                              eval_bdd(ports['ic'], env), mask_var, eval_bdd(ports['ie'], env)])
            selected = mk(bank * 5 + col, 0, 1)
            expected_output = ite(mask_var, ite(selected, 0, 1), selected)
            assert output == expected_output, ('Bank/class BDD mismatch', col, bank)
            bdd_proofs.append({'ClassBit': col, 'Bank': bank, 'Root': output, 'ExpectedRoot': expected_output})
        proofs.append({'ClassBit': col, 'FinalAdderCell': name, 'INIT_LUT5B': params['INIT_LUT5B'],
                       'Output': ports['ofb'], 'Operation': 'mask XOR selected independent class bit'})
    return rows, {'BankCount': 25, 'WordsCompared': 102400, 'BankSelectTruthRows': 25 * 32 * 2 * 2,
                  'RegisteredSelectTruthRows': 40, 'Banks': bankinfo, 'Proofs': proofs,
                  'IndependentBankBitBDDProofs': bdd_proofs, 'BDDNodes': len(nodes)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run', type=Path)
    ap.add_argument('--tag', required=True)
    args = ap.parse_args()
    run = args.run.resolve()
    out = EVIDENCE / 'audio22/rom-proofs' / args.tag
    assert not out.exists(), out
    gate = run / 'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    before = base.sha(gate)
    text = base.read(gate)
    memories = base.memories(text)
    graph = {}
    for width in range(1, 7):
        for _, (params, ports) in derive.cells(text, f'AL_MAP_LUT{width}').items():
            if all(pin in ports for pin in 'abcdef'[:width]):
                graph[ports['o']] = (params['INIT'], [ports[pin] for pin in 'abcdef'[:width]])
    seq = derive.cells(text, 'AL_MAP_SEQ_GSR')

    def evaluate(node, env):
        if node in env:
            return env[node]
        if node in ('0', '1', "1'b0", "1'b1"):
            return int(node[-1])
        assert node in graph, ('Unresolved proof leaf', node)
        init, inputs = graph[node]
        value = (init >> sum(evaluate(signal, env) << i for i, signal in enumerate(inputs))) & 1
        env[node] = value
        return value

    rows, rotation = rotation_proof(run, memories, graph, seq, derive.cells(text, 'PH1P_PHY_LSLICE'), evaluate)
    shape = [m for m in memories if '/shape_mode$shape_guard/templates/' in m['Name']]
    assert len(shape) == 1
    memory = shape[0]
    addresses = base.word_address_bits(memory)
    assert addresses == [f'u_p14_pipeline/scene_mode$scene/card_index[{i}]' for i in range(10)] + ['0', '0']
    pins = base.port_bits(memory)
    mapping = {str(i): int(match[1]) for i, x in enumerate(pins) if (match := re.search(r'/templates/data\[(\d+)\]$', x))}
    assert mapping == {'0': 0, '1': 1, '2': 2}
    assert memory['Params']['CSB0'] == memory['Params']['CSB1'] == '1' and memory['Params']['CSB2'] == 'SIG'
    assert base.bits(memory['Ports']['csb'], memory['Declarations'])[2] == 'u_p14_pipeline/shape_mode$shape_guard/rom_enable'
    rows[memory['Name']] = {'Kind': 'shape', 'Port': 'b', 'LogicalBase': 0, 'LogicalOutputBits': mapping,
                           'OutputPinsLSB': pins, 'WordAddressPinsLSB': addresses, 'AddressAndSelectReviewed': True}
    font = [m for m in memories if m['Name'].startswith('u_p17_display/panel/font/')]
    assert len(font) == 3
    font_rows = []
    panel = base.read(run / 'rtl/pixel22_panel.v')
    assert 'bottom_panel=pixel_y>=608 && pixel_y<712' in panel
    assert 'local_y=bottom_panel ? pixel_y-612:pixel_y-12' in panel
    assert '.row(local_y[4:1])' in panel
    for memory in font:
        pins = base.port_bits(memory)
        mapping = {str(i): int(re.fullmatch(r'u_p17_display/panel/font_bits\[(\d+)\]', pin)[1])
                   for i, pin in enumerate(pins)}
        addresses = base.word_address_bits(memory)
        assert len(addresses) == 12
        assert addresses[4:] == [f'u_p17_display/panel/font/glyph[{i}]' for i in range(8)]
        for y in range(1024):
            env = {f'u_p17_display/diagnostic_panel/pixel_y[{i}]': (y >> i) & 1 for i in range(10)}
            observed = sum(evaluate(node, env) << bit for bit, node in enumerate(addresses[:4]))
            expected = ((y - (612 if 608 <= y < 712 else 12)) >> 1) & 15
            assert observed == expected, (memory['Name'], y, observed, expected)
        assert all(memory['Params']['CS' + port + str(i)] == '1' for port in ('A', 'B') for i in range(3))
        assert memory['Params']['REGMODE_B'] == 'NOREG' and memory['Params']['CLKBMUX'] == 'SIG'
        assert memory['Ports']['clkb'] == 'S_hdmi_pixel_clk'
        rows[memory['Name']] = {'Kind': 'font', 'Port': 'b', 'LogicalBase': 0, 'LogicalOutputBits': mapping,
                               'OutputPinsLSB': pins, 'WordAddressPinsLSB': addresses, 'AddressAndSelectReviewed': True}
        font_rows.append({'Instance': memory['Name'], 'YInputsChecked': 1024, 'GlyphAddressDirect': True})

    prefix = 'u_p17_display/logo/'
    index = [int(x, 16) for x in base.read(run / 'anlogic_logo_index.mem').split()]
    palette = [int(x, 16) for x in base.read(run / 'anlogic_logo_palette.mem').split()]
    assert len(index) == 16384 and len(palette) == 1024
    index_roms = [m for m in memories if m['Name'].startswith(prefix + 'ramread0_')]
    palette_roms = [m for m in memories if m['Name'].startswith(prefix + 'ramread1_')]
    assert len(index_roms) == 8 and len(palette_roms) == 2
    bank_info = []
    for memory in index_roms:
        assert memory['Params']['DATA_WIDTH_B'] == '5'
        words = base.init_decode(memory['Values'], 5)
        candidates = [(bank, half) for bank in range(4) for half in range(2)
                      if words == [(value >> (half * 5)) & 31 for value in index[bank * 4096:(bank + 1) * 4096]]]
        assert len(candidates) == 1, (memory['Name'], candidates)
        bank, half = candidates[0]
        pins = base.port_bits(memory)
        addresses = base.word_address_bits(memory)
        assert addresses == [prefix + f's1_address_reg[{i}]_syn_2' for i in range(12)]
        for group in range(4):
            env = {prefix + f's1_address_reg[{i}]_syn_2': (group >> (i - 12)) & 1 for i in (12, 13)}
            for port in ('a', 'b'):
                selected = 1
                for i, signal in enumerate(base.bits(memory['Ports']['cs' + port], memory['Declarations'])):
                    mode = memory['Params']['CS' + port.upper() + str(i)]
                    selected &= int(mode) if mode in ('0', '1') else evaluate(signal, env.copy()) ^ (mode == 'INV')
                assert selected == int(group == bank), (memory['Name'], group, selected, bank)
        assert memory['Params']['REGMODE_B'] == 'NOREG'
        assert memory['Params']['CLKBMUX'] == 'SIG' and memory['Ports']['clkb'] == 'S_hdmi_pixel_clk'
        rows[memory['Name']] = {'Kind': 'logo-index', 'Port': 'b', 'LogicalBase': bank * 4096,
                               'LogicalOutputBits': {str(i): half * 5 + i for i in range(5)},
                               'OutputPinsLSB': pins, 'WordAddressPinsLSB': addresses, 'AddressAndSelectReviewed': True}
        bank_info.append({'Bank': bank, 'Half': half, 'Instance': memory['Name'], 'Outputs': pins})
    assert sorted((x['Bank'], x['Half']) for x in bank_info) == [(b, h) for b in range(4) for h in range(2)]
    selectors = [prefix + f's1_address_reg[12]_syn_19[{i}]' for i in range(2)]
    register_proofs = []
    for i, target in enumerate(selectors):
        matches = [(name, p, q) for name, (p, q) in seq.items() if q.get('q') == target]
        assert len(matches) == 1
        name, params, ports = matches[0]
        assert ports['d'] == prefix + f's1_address_reg[{12 + i}]_syn_2'
        assert ports['clk'] == 'S_hdmi_pixel_clk'
        assert all(params[k] == v for k, v in {'CEMUX': '1', 'CLKMUX': 'SIG', 'DFFMODE': 'FF', 'SRMUX': '0'}.items())
        register_proofs.append({'Cell': name, 'Parameters': params, 'Ports': ports})
    mux_checks = 0
    for bit in range(10):
        sources = [next(x['Outputs'][bit % 5] for x in bank_info if x['Bank'] == b and x['Half'] == bit // 5)
                   for b in range(4)]
        target = prefix + f's2_index_b[{bit}]'
        for bank in range(4):
            for pattern in range(16):
                env = {selectors[i]: (bank >> i) & 1 for i in range(2)}
                env.update({signal: (pattern >> b) & 1 for b, signal in enumerate(sources)})
                assert evaluate(target, env) == ((pattern >> bank) & 1), (bit, bank, pattern)
                mux_checks += 1
        matches = [(name, p, q) for name, (p, q) in seq.items() if q.get('q') == prefix + f's2_index[{bit}]']
        assert len(matches) == 1
        name, params, ports = matches[0]
        assert ports['d'] == target and ports['clk'] == 'S_hdmi_pixel_clk'
        assert all(params[k] == v for k, v in {'CEMUX': '1', 'CLKMUX': 'SIG', 'DFFMODE': 'FF', 'SRMUX': '0'}.items())
        register_proofs.append({'Cell': name, 'Parameters': params, 'Ports': ports})
    for memory in palette_roms:
        pins = base.port_bits(memory)
        mapping = {str(i): int(match[1]) for i, pin in enumerate(pins)
                   if (match := re.fullmatch(re.escape(prefix) + r's3_color\[(\d+)\]', pin))}
        assert sorted(mapping.values()) in (list(range(20)), list(range(20, 24)))
        width = int(memory['Params']['DATA_WIDTH_B'])
        words = base.init_decode(memory['Values'], width)
        for a, value in enumerate(words):
            expected = palette[a] if a < 1024 else 0
            assert all(((value >> int(pb)) & 1) == ((expected >> lb) & 1) for pb, lb in mapping.items())
            assert all((value >> i) & 1 == 0 for i in range(width) if str(i) not in mapping)
        addresses = base.word_address_bits(memory)
        assert addresses == [prefix + f's2_index_b[{i}]' for i in range(10)] + (['0', '0'] if width == 5 else [])
        assert all(memory['Params']['CS' + p + str(i)] == '1' for p in ('A', 'B') for i in range(3))
        # OUTREG supplies the second edge after mux inputs: address sampling,
        # then registered palette color. This binds absorbed address registers.
        assert memory['Params']['REGMODE_B'] == 'OUTREG' and memory['Params']['OCEBMUX'] == '1'
        assert memory['Params']['RSTBMUX'] == '0' and memory['Params']['CLKBMUX'] == 'SIG'
        assert memory['Ports']['clkb'] == 'S_hdmi_pixel_clk'
        rows[memory['Name']] = {'Kind': 'logo-palette', 'Port': 'b', 'LogicalBase': 0, 'LogicalOutputBits': mapping,
                               'OutputPinsLSB': pins, 'WordAddressPinsLSB': addresses, 'AddressAndSelectReviewed': True}
    assert len(rows) == 39
    assert base.sha(gate) == before
    out.mkdir(parents=True)
    sources = [gate, run / 'templates.mem', run / 'rtl/pixel14_rotation_matcher.v', run / 'rtl/pixel14_block_shape_guard.v',
               run / 'rtl/pixel22_panel.v', run / 'rtl/sc520_logo_pipeline.v', run / 'rtl/pixel22_font_rom.v',
               run / 'anlogic_logo_index.mem', run / 'anlogic_logo_palette.mem', Path(__file__), Path(derive.__file__), Path(base.__file__)]
    sealed = []
    for source in sources:
        source = source.resolve()
        if source.is_relative_to(run):
            sealed.append(base.artifact(source))
        else:
            target = out / 'inputs' / source.name
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(source.read_bytes())
            assert base.sha(source) == base.sha(target)
            sealed.append({**base.artifact(target), 'RuntimeSourcePath': str(source)})
    proof_path = out / 'proof.json'
    proof = {'Verified': True, 'SynNetlistSHA256': before, 'Sources': sealed, 'RotationProof': rotation,
             'FontRowProofs': font_rows, 'LogoIndexBanks': bank_info, 'LogoMuxTruthRows': mux_checks,
             'LogoRegisteredSelectorsAndIndex': register_proofs, 'LogoPaletteOUTREGAddressAbsorptionReviewed': True,
             'Scope': 'Current netlist: rotation INIT/address/bank selects/registered selectors/125 independent bank-class BDDs; shape address/enable; font row address truth table; Logo INIT/bank selects/registered selectors/mux/palette address and output mode. Routed connections and timing require separate audit.'}
    base.emit(proof_path, proof)
    for row in rows.values():
        row['Evidence'] = [base.artifact(proof_path)]
    base.emit(out / 'bindings.json', {'SynNetlistSHA256': before, 'Proof': base.artifact(proof_path), 'Bindings': rows})
    print(json.dumps({'Verified': True, 'Bindings': len(rows), 'LogoMuxTruthRows': mux_checks, 'Proof': str(proof_path)}))


if __name__ == '__main__':
    main()
