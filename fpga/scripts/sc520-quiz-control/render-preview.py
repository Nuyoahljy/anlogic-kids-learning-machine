#!/usr/bin/env python3
"""Render an offline display preview from an actual quiz RTL simulation CSV.

Python standard library only. No generated stimulus and no claims of HDMI or
physical camera/audio verification. Invalid evidence is rejected before output.
"""
import argparse
import csv
import hashlib
import html
import io
import json
from pathlib import Path
import sys

FIELDS = (
    "cycle", "mode", "phase", "question", "target", "score", "feedback", "item",
    "source_test", "armed", "audio_fault", "answer_valid", "answer_correct",
)
BOOL_FIELDS = ("source_test", "armed", "audio_fault", "answer_valid", "answer_correct")
ITEMS = ["未识别 / 无目标", "红色圆形", "红色方形", "红色三角形", "黄色圆形",
         "黄色方形", "黄色三角形", "蓝色圆形", "蓝色方形", "蓝色三角形"]


def read_trace(path):
    raw = path.read_bytes()
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    missing = set(FIELDS) - set(reader.fieldnames or [])
    if missing:
        raise ValueError("CSV 缺少字段: " + ", ".join(sorted(missing)))
    rows = []
    for line, source in enumerate(reader, 2):
        try:
            row = {key: int(source[key], 10) for key in FIELDS}
        except (ValueError, TypeError) as error:
            raise ValueError(f"CSV 第 {line} 行必须是完整十进制整数") from error
        checks = [
            (row["cycle"] >= 0, "cycle 不能为负数"),
            (not rows or row["cycle"] > rows[-1]["cycle"], "cycle 必须严格递增"),
            (0 <= row["score"] <= 10, "score 超出 0..10"),
            (row["mode"] in (0, 1, 2), "mode 超出当前三模式"),
            (row["phase"] in (0, 1, 2, 3), "phase 超出当前状态映射"),
            (row["feedback"] in (0, 1, 2, 3), "feedback 超出当前反馈映射"),
            (0 <= row["question"] <= 10, "question 超出 0..10"),
            (row["mode"] != 2 or 1 <= row["question"] <= 10,
             "问答模式题号必须为 1..10"),
            (0 <= row["target"] <= 9, "target 超出当前九类范围"),
            (0 <= row["item"] <= 15, "item 超出四位输入范围"),
            (not (row["source_test"] and row["answer_valid"]),
             "测试来源产生正式答案事件，禁止生成通过预览"),
        ]
        checks.extend((row[key] in (0, 1), f"{key} 必须为 0 或 1") for key in BOOL_FIELDS)
        for condition, message in checks:
            if not condition:
                raise ValueError(f"CSV 第 {line} 行: {message}")
        rows.append(row)
    if not rows:
        raise ValueError("CSV 没有仿真采样数据")
    return rows, hashlib.sha256(raw).hexdigest().upper()


TEMPLATE = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SC520 问答交互 · RTL 仿真预览</title>
<style>
:root{color-scheme:dark;--bg:#101624;--panel:#1b2639;--muted:#adbbd1;--line:#34445e;--accent:#77e2c3;--warn:#ffcf73}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#f4f7fc;font:16px/1.65 "Microsoft YaHei","Noto Sans CJK SC",sans-serif}
main{max-width:1120px;margin:0 auto;padding:28px 24px 44px}h1{font-size:29px;line-height:1.35;margin:12px 0}h2{font-size:18px;margin:0 0 12px}p{margin:8px 0}.eyebrow{color:var(--accent);letter-spacing:.08em;font-size:13px;font-weight:700}.muted{color:var(--muted)}.notice{background:#473b24;color:#ffe8ae;border:1px solid #a9843e;padding:12px 16px;border-radius:12px;margin:18px 0}.screen{border:1px solid var(--line);border-radius:20px;overflow:hidden;box-shadow:0 18px 50px #0004}.top{display:flex;justify-content:space-between;gap:16px;align-items:center;padding:18px 22px;background:#26354e}.mode{font-size:23px;font-weight:700}.badge{display:inline-block;background:#384860;border:1px solid #6b819f;border-radius:99px;padding:2px 10px;font-size:13px}.source-test{background:#5d3d18;color:#ffe3a7;border-color:#b0853e}.body{display:grid;grid-template-columns:1.2fr 1fr;gap:24px;padding:30px;background:var(--panel)}.prompt{font-size:29px;line-height:1.5;font-weight:700;margin:14px 0 24px;min-height:86px}.stage{font-size:14px;color:var(--accent)}.objectbox{border-radius:16px;border:1px dashed #647692;min-height:245px;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:12px;background:#152133}.objectbox svg{width:120px;height:120px}.objlabel{font-size:23px;font-weight:700}.shape-none{color:var(--muted);font-size:58px}.result{padding:18px 22px;background:#26354e;display:flex;align-items:center;justify-content:space-between;gap:16px}.feedback{font-size:22px;font-weight:700}.score{white-space:nowrap;font-size:19px}.score b{font-size:36px;color:var(--accent)}.subtext{color:var(--muted);font-size:14px}.fault{padding:12px 22px;color:#ffdda0;background:#503d23}.hidden{display:none}.controls,.states,.audit{border:1px solid var(--line);background:var(--panel);padding:20px 22px;border-radius:16px;margin-top:20px}.timeline{display:flex;gap:12px;align-items:center}.timeline input{flex:1;min-width:80px;accent-color:var(--accent)}button,select{font:inherit;color:#f4f7fc;background:#26354e;border:1px solid #586d89;border-radius:8px;padding:8px 12px}button{cursor:pointer}button:hover,button:focus-visible{border-color:var(--accent)}button:disabled{opacity:.4;cursor:default}select{max-width:100%;width:100%;margin-top:12px}label{color:var(--muted)}.state-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.state-card{text-align:left;padding:12px;font-size:14px}.state-card strong{display:block;color:var(--accent);margin-bottom:4px}.audit dl{display:grid;grid-template-columns:110px 1fr;gap:8px;margin:0}.audit dt{color:var(--muted)}.audit dd{margin:0;overflow-wrap:anywhere;font-family:Consolas,monospace;font-size:13px}.footer{margin-top:20px;font-size:13px;color:var(--muted)}
@media(max-width:700px){main{padding:18px 14px}.body{grid-template-columns:1fr;padding:20px;gap:12px}.prompt{min-height:0;font-size:25px}.objectbox{min-height:185px}.top,.result{padding:14px;align-items:flex-start}.top{flex-direction:column}.mode{font-size:20px}.feedback{font-size:19px}.score b{font-size:28px}.timeline{flex-wrap:wrap}.audit dl{grid-template-columns:1fr}}
</style></head><body><main>
<div class="eyebrow">SC520 · 问答计分与交互逻辑</div>
<h1>RTL 仿真预览 · 音频模拟</h1>
<p class="muted">从实际仿真 CSV 读取状态，可选择时间点查看题目、正误反馈与分数。</p>
<div class="notice">本页是独立的软件显示预览。摄像输入、按键和音频均为模拟；不代表实物识别、HDMI 画面或实际出声已通过。</div>
<section class="screen" aria-label="模拟屏幕反馈">
 <div class="top"><div class="mode" id="mode"></div><div><span class="badge" id="source"></span> <span class="badge">音频模拟</span></div></div>
 <div class="body"><div><div class="stage" id="stage"></div><div class="prompt" id="prompt"></div><div id="action" class="muted"></div><p class="subtext" id="answer-event"></p></div><div class="objectbox"><div id="shape"></div><div class="objlabel" id="item"></div><span class="subtext">当前模拟识别输入</span></div></div>
 <div class="result"><div><div class="feedback" id="feedback"></div><div class="subtext" id="feedback-detail"></div></div><div class="score">分数 <b id="score"></b> / 10</div></div>
 <div class="fault hidden" id="fault">音频故障（模拟） · 控制与显示继续运行，实际设备的恢复方式待手册确认。</div>
</section>
<section class="controls"><h2>时间点回放</h2><div class="timeline"><button id="prev" type="button">上一状态</button><input type="range" id="timeline" min="0" step="1" aria-label="选择仿真采样"><button id="next" type="button">下一状态</button></div><p class="subtext" id="position"></p><label for="milestone">跳转到关键状态</label><select id="milestone"></select></section>
<section class="states"><h2>代表状态快照</h2><p class="subtext">从日志抽取首次出现的模式、反馈、计分、来源或故障组合；全部时间点可在上方查看。</p><div class="state-grid" id="cards"></div></section>
<section class="audit"><h2>证据来源</h2><dl><dt>CSV 文件</dt><dd>@@SOURCE@@</dd><dt>SHA-256</dt><dd>@@HASH@@</dd><dt>采样 / 答案事件</dt><dd>@@COUNTS@@</dd><dt>字段检查</dt><dd>score 0..10；问答题号 1..10；测试来源无正式答案事件；字段、布尔量与时序检查通过</dd></dl></section>
<p class="footer">对象映射：1 红色圆形 · 2 红色方形 · 3 红色三角形 · 4 黄色圆形 · 5 黄色方形 · 6 黄色三角形 · 7 蓝色圆形 · 8 蓝色方形 · 9 蓝色三角形。此页面没有连接真实摄像头或播放器，也没有生成硬件镜像。</p>
</main><script id="trace-data" type="application/json">@@ROWS@@</script>
<script>
"use strict";
const rows=JSON.parse(document.getElementById("trace-data").textContent);
const items=@@ITEMS@@, modes=["待机模式","探索模式","问答模式"], phases=["待机 / 探索","等待答案","反馈中","本轮结束"], feedbacks=["等待操作","回答正确","再试一次","正确答案"];
const el=id=>document.getElementById(id), put=(id,value)=>{el(id).textContent=value;};
const itemName=id=>items[id] || "不支持的对象（编号 "+id+"）";
let selected=0;
const milestoneKeys=["mode","phase","question","target","score","feedback","source_test","audio_fault","armed"];
const milestones=rows.map((r,i)=>i).filter(i=>i===0 || rows[i].answer_valid || milestoneKeys.some(k=>rows[i][k]!==rows[i-1][k]));
function shortLabel(r){return "周期 "+r.cycle+" · "+modes[r.mode]+(r.mode===2?" · 第 "+r.question+" 题":"")+" · "+r.score+" 分 · "+(r.audio_fault?"音频故障":feedbacks[r.feedback])+(r.source_test?" · 测试来源":"");}
for(const i of milestones){const option=document.createElement("option");option.value=i;option.textContent=shortLabel(rows[i]);el("milestone").appendChild(option);}
function drawItem(id){
 el("shape").replaceChildren();
 if(id<1||id>9){const blank=document.createElement("span");blank.className="shape-none";blank.textContent="?";el("shape").appendChild(blank);return;}
 const ns="http://www.w3.org/2000/svg",svg=document.createElementNS(ns,"svg");svg.setAttribute("viewBox","0 0 120 120");svg.setAttribute("aria-hidden","true");
 const kind=(id-1)%3,shape=document.createElementNS(ns,["circle","rect","polygon"][kind]);
 const attrs=kind===0?{cx:60,cy:60,r:45}:kind===1?{x:16,y:16,width:88,height:88,rx:8}:{points:"60,10 112,106 8,106"};
 for(const [k,v] of Object.entries(attrs))shape.setAttribute(k,v);
 shape.setAttribute("fill",["#ef767e","#f2cd69","#76a8ef"][Math.floor((id-1)/3)]);shape.setAttribute("stroke","#ffffff");shape.setAttribute("stroke-width","3");svg.appendChild(shape);el("shape").appendChild(svg);
}
function render(index){
 selected=Math.max(0,Math.min(rows.length-1,Number(index)));const r=rows[selected];
 put("mode",modes[r.mode]);put("source",r.source_test?"测试来源 · 禁止正式计分":"模拟摄像输入");el("source").className="badge"+(r.source_test?" source-test":"");
 put("stage",r.mode===2?"第 "+r.question+" 题 / 共 10 题 · "+phases[r.phase]:phases[r.phase]);
 put("prompt",r.mode===2?(r.phase===3?"本轮问答已结束":"请找出"+itemName(r.target)):(r.mode===1?"认识身边的颜色和形状":"请放置积木，或切换模式"));
 put("action",r.source_test?"当前为内置测试来源，不能提交正式答案。":r.mode===2?(r.phase===3?"可清分退出，或切换模式开启下一轮。":r.phase===2?"正在给出反馈；请先移走积木，再开始下一次作答。":r.armed?"已确认移走，现在放入一个积木作答。":"请先确认移走旧物体，再放入作答。"):(r.mode===1?"一次放入只触发一次自动名称播报（模拟）。":"用模式键选择探索或问答。"));
 put("item",itemName(r.item));drawItem(r.item);put("score",r.score);
 put("feedback",r.phase===3?"完成 10 题":r.feedback===3?"正确答案："+itemName(r.target):feedbacks[r.feedback]);
 put("feedback-detail",r.feedback===1?"本次正确答案加 1 分":r.feedback===2?"不加分；确认移走后可再次作答":r.feedback===3?"连续错答达到上限；本题不加分":r.phase===3?"本轮总分已保留":"未知或抖动不视为新的放入");
 put("answer-event",r.answer_valid?"本采样发生一次答案事件："+(r.answer_correct?"正确":"错误"):"本采样无新答案事件");
 el("fault").classList.toggle("hidden",!r.audio_fault);el("timeline").value=selected;
 put("position","采样 "+(selected+1)+" / "+rows.length+" · RTL 时钟周期 "+r.cycle+" · 只回放记录，不生成新的仿真结果");
 el("prev").disabled=selected===0;el("next").disabled=selected===rows.length-1;
 let current=milestones[0];for(const i of milestones){if(i>selected)break;current=i;}el("milestone").value=current;
}
el("timeline").max=rows.length-1;el("timeline").addEventListener("input",e=>render(e.target.value));el("milestone").addEventListener("change",e=>render(e.target.value));
el("prev").addEventListener("click",()=>{const older=milestones.filter(i=>i<selected);render(older.length?older[older.length-1]:0);});
el("next").addEventListener("click",()=>render(milestones.find(i=>i>selected)??rows.length-1));
const seen=new Set();let cards=0;
for(const i of milestones){const r=rows[i],signature=[r.mode,r.phase,r.feedback,r.score,r.source_test,r.audio_fault].join(":");if(seen.has(signature)||cards>=24)continue;seen.add(signature);cards++;
 const button=document.createElement("button");button.className="state-card";button.type="button";const strong=document.createElement("strong");strong.textContent=modes[r.mode]+" · "+(r.phase===3?"一轮结束":feedbacks[r.feedback]);const span=document.createElement("span");span.textContent="周期 "+r.cycle+" · "+(r.mode===2?"第 "+r.question+" 题 · ":"")+r.score+" 分"+(r.source_test?" · 测试来源":"")+(r.audio_fault?" · 音频故障":"");button.append(strong,span);button.addEventListener("click",()=>render(i));el("cards").appendChild(button);}
render(milestones.find(i=>rows[i].mode===2&&rows[i].phase===1)??0);
</script></body></html>
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", type=Path, required=True, help="实际 RTL 仿真 CSV")
    parser.add_argument("--output", type=Path, required=True, help="独立离线 HTML 输出")
    args = parser.parse_args()
    if args.trace.resolve() == args.output.resolve():
        parser.error("输出路径不能覆盖输入 CSV")
    try:
        rows, digest = read_trace(args.trace)
        substitutions = {
            "@@SOURCE@@": html.escape(str(args.trace.resolve())),
            "@@HASH@@": digest,
            "@@COUNTS@@": f"{len(rows)} 行 / {sum(r['answer_valid'] for r in rows)} 次答案事件",
            "@@ROWS@@": json.dumps(rows, ensure_ascii=False, separators=(",", ":")),
            "@@ITEMS@@": json.dumps(ITEMS, ensure_ascii=False),
        }
        result = TEMPLATE
        for marker, value in substitutions.items():
            result = result.replace(marker, value)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result, encoding="utf-8")
        print(f"PREVIEW rows={len(rows)} answer_events={sum(r['answer_valid'] for r in rows)} trace_sha256={digest} output={args.output.resolve()}")
    except (ValueError, OSError, UnicodeError) as error:
        print(f"PREVIEW_ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
