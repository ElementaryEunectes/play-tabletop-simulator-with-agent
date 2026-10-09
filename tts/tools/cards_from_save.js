// cards_from_save.js - build card.ps1's text library from a TTS SAVE instead of from the live table.
//
// WHY THE SAVE (measured 2026-10-09): asking the running game for a card's description returns it
// TRUNCATED - "本回合中，目标角色下次受到的伤害-3。（每回合中每个角色最多食用1..." and nothing more -
// which is a TTS-side limit on what getDescription()/the object listing hands out. The save file
// carries the same field COMPLETE, so the save is the source for the library. It also reaches cards
// that sit inside a Deck, which the bridge cannot even address by guid.
//
// card.ps1 reads: 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源
//   node tts/tools/cards_from_save.js <save.json> <out.md>
const fs = require('fs');

const [, , saveFile, outFile] = process.argv;
if (!saveFile || !outFile) { console.error('usage: node cards_from_save.js <save.json> <out.md>'); process.exit(2); }

const save = JSON.parse(fs.readFileSync(saveFile, 'utf8'));

const found = [];
// Only real game pieces. WHY: Notecards, counters and the table's own signs also carry a
// Description, and pulling those in buried the 173 real cards in 355 rows of instructions
// ("请对战双方选择颜色为青色与棕色" showed up as a card type - measured 2026-10-09).
const CARD_NAMES = new Set(['Card', 'Deck', 'DeckCustom', 'Custom_Deck', 'Custom_Token', 'Custom_Tile']);
function walk(list, where) {
    for (const o of list || []) {
        if (o && o.Description && String(o.Description).trim() !== '' && CARD_NAMES.has(o.Name)) {
            found.push({
                guid: o.GUID || '',
                name: o.Nickname || o.Name || '',
                desc: String(o.Description),
                name2: o.Name || '',
                where: where,
            });
        }
        walk(o && o.ContainedObjects, where);
        walk(o && o.States && Object.keys(o.States).map((k) => o.States[k]), where);
    }
}
walk(save.ObjectStates, 'top');

const seen = new Set();
const seenNames = new Set();
const rows = [];
for (const f of found) {
    if (seen.has(f.guid)) continue;
    seen.add(f.guid);
    const desc = f.desc.replace(/\r\n/g, '\n');
    const segs = desc.split(/-{3,}/).map((s) => s.trim()).filter(Boolean);
    const head = segs[0] || '';
    const effect = segs.slice(1).join(' ').replace(/\s+/g, ' ').trim() || head;
    let type = '', owner = '', cost = '';
    const ch = /^角色牌\s*生命值：(\d+)\s*(\S+)\s*(\S+)/.exec(head);
    if (ch) { type = '角色牌 HP' + ch[1]; owner = ch[2]; cost = ch[3]; }
    else {
        const act = /^(行动牌[^\s(]*)\s*(?:\(([^)]*)\))?/.exec(head);
        if (act) { type = act[1]; cost = act[2] ? '(' + act[2] + ')' : ''; }
        else { type = head.split(/\s+/)[0] || ''; }
    }
    // A mat or a sign whose text happens to sit in Description is not a card: the real ones start
    // with a card kind, so anything else is dropped instead of being shown as a card named after a
    // sentence ("不要乱丢，注意顺序！..." was one - measured 2026-10-09).
    if (!/^(角色牌|行动牌|召唤物|出战状态|事件牌|装备牌|支援牌|场地牌|料理|道具)/.test(head)) continue;
    // same name twice = the same card saved in two places; keep the one with the longer text
    const key = f.name;
    if (seenNames.has(key)) {
        const prev = rows.findIndex((r) => r.name === key);
        if (prev >= 0 && rows[prev].effect.length >= effect.length) continue;
        if (prev >= 0) rows.splice(prev, 1);
    }
    seenNames.add(key);
    rows.push({ name: f.name, type, owner, cost, effect, src: 'save/' + f.guid });
}

if (!rows.length) { console.error('no described objects found - nothing written'); process.exit(1); }

const esc = (s) => String(s).replace(/\|/g, '/').replace(/\r?\n/g, ' ').trim();
const head = [
    '# ' + outFile.replace(/^.*[\\/]/, '') + ' - card text library (generated, do not hand-edit)',
    '',
    '> Built by `tts\\tools\\cards_from_save.js` from a save file, NOT from the live table: TTS hands',
    '> out descriptions truncated ("...最多食用1"), while the save carries them complete.',
    '> Columns are fixed - card.ps1 reads them: 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源.',
    '',
    '| 名称 | 类型 | 归属 | 费用 | 效果要点 | 来源 |',
    '|---|---|---|---|---|---|',
];
fs.writeFileSync(outFile, head.concat(rows.map((r) => '| ' + [r.name, r.type, r.owner, r.cost, r.effect, r.src].map(esc).join(' | ') + ' |'), '').join('\n'), 'utf8');

const byType = {};
rows.forEach((r) => { byType[r.type] = (byType[r.type] || 0) + 1; });
const longest = rows.reduce((a, r) => Math.max(a, r.effect.length), 0);
console.log('wrote ' + outFile + ': ' + rows.length + ' card(s); longest effect ' + longest + ' chars');
console.log('types: ' + JSON.stringify(byType));
