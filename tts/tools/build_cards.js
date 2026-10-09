// build_cards.js - turn a `container:<guid>:full` reply into card.ps1's text library.
//
// WHY: the card library (cache\<game>_cards.md) is the one place card.ps1 can query, and until now
// the face text existed only inside the mod - container: cut it to 60 chars, and obj_index/live_index
// never carried it at all. With `:full` the whole face comes back as
//   guid|name|nickname|quantity|description
// where description is "type 生命值：N region weapon ---------- skill(cost) effect ... ---------- ...".
// card.ps1 reads a markdown table: 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源
//
//   node tts/tools/build_cards.js <out.md> <reply.json> [<reply.json> ...]
const fs = require('fs');

const outFile = process.argv[2];
const inputs = process.argv.slice(3);
if (!outFile || !inputs.length) {
    console.error('usage: node build_cards.js <out.md> <containerFullReply.json>...');
    process.exit(2);
}

const rows = [];
let skipped = 0;
for (const f of inputs) {
    // ⛔ strip a UTF-8 BOM: ds.ps1's output goes through PowerShell's redirect, which prepends one,
    // and JSON.parse dies on it with a message about an unexpected character at position 0.
    let text = fs.readFileSync(f, 'utf8');
    if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
    const reply = JSON.parse(text);
    const cm = reply.customMessage || {};
    if (cm.ok !== true) { console.error('reply not ok in ' + f + ': ' + JSON.stringify(cm.err)); continue; }
    let lines = cm.lines;
    if (typeof lines === 'string') lines = JSON.parse(lines);
    for (const l of lines) {
        const p = String(l).split('|');
        const guid = p[0] || '';
        const name = p[1] || '';
        const nick = p[2] || '';
        const desc = (p[4] || '').trim();
        if (!desc) { skipped++; continue; }          // deck contents expose no description (see note)
        // Descriptions look like one of:
        //   角色牌 生命值：10 璃月 弓 ---------- 普通攻击：流天射术(1冰 2任意) 造成2点物理伤害。 ---------- ...
        //   行动牌(2同色) ---------- 效果：... ---------- ...
        // Only the HEAD is parsed (it is regular); the effect keeps the whole remaining text, because
        // splitting on the ---------- dividers loses the second half of a card ("吃到一半" - measured).
        const segs = desc.split(/-{3,}/).map((s) => s.trim()).filter(Boolean);
        const head = segs[0] || '';
        const effect = segs.slice(1).join(' ').replace(/\s+/g, ' ').trim() || head;
        let type = '', owner = '', cost = '', hp = '';
        const ch = /^角色牌\s*生命值：(\d+)\s*(\S+)\s*(\S+)/.exec(head);
        if (ch) {
            type = '角色牌';
            hp = ch[1];
            owner = ch[2];
            cost = ch[3];                             // weapon, for a character card
        } else {
            const act = /^(行动牌[^\s(]*)\s*(?:\(([^)]*)\))?/.exec(head);
            if (act) { type = act[1]; cost = act[2] ? '(' + act[2] + ')' : ''; }
            else { type = head.split(/\s+/)[0] || ''; }
        }
        rows.push({
            name: name || nick || guid,
            type: hp ? (type + ' HP' + hp) : type,
            owner: owner,
            cost: cost,
            effect: effect,
            src: 'container:' + (cm.guid || '?') + '/' + guid,
        });
    }
}
if (!rows.length) { console.error('no rows built - nothing written'); process.exit(1); }

const esc = (s) => String(s).replace(/\|/g, '/').replace(/\r?\n/g, ' ').trim();
const head = [
    '# ' + outFile.replace(/^.*[\\/]/, '') + ' - card text library (generated, do not hand-edit)',
    '',
    '> Built by `tts\\tools\\build_cards.js` from `container:<guid>:full` replies on a live table.',
    '> card.ps1 reads this table; the columns are fixed: 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源.',
    '',
    '| 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源 |',
    '|---|---|---|---|---|---|',
];
const body = rows.map((r) => '| ' + [r.name, r.type, r.owner, r.cost, r.effect, r.src].map(esc).join(' | ') + ' |');
fs.writeFileSync(outFile, head.concat(body, '').join('\n'), 'utf8');
console.log('wrote ' + outFile + ': ' + rows.length + ' card(s), skipped ' + skipped + ' description-less entr(ies)');
const byType = {};
rows.forEach((r) => { byType[r.type] = (byType[r.type] || 0) + 1; });
console.log('types: ' + JSON.stringify(byType));
