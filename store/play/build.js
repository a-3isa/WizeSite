/* Generates all Google Play listing HTML canvases at exact pixel sizes.
   Rendered to PNG by Chrome headless (see render.sh). On-brand with the app's
   v2 dark theme. No external deps. */
const fs = require("fs");
const path = require("path");

const HTML_DIR = path.join(__dirname, "html");
fs.mkdirSync(HTML_DIR, { recursive: true });

const FONTS =
  '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
  '<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0&display=swap" rel="stylesheet">';

// v2 dark theme tokens.
const THEME = `
:root{
  --accent:#ff6d00;--accent2:#ff8a33;--onacc:#16130f;
  --income:#35d08a;--expense:#ff6b6b;--warn:#fbbf24;
  --bg:#0e1116;--surface:#171c23;--surface2:#1e242d;--surface3:#262d38;
  --border:#262d38;--borderS:#333c49;--text:#edf0f4;--muted:#949fad;--faint:#6a7482;
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter',system-ui,sans-serif;background:var(--bg);color:var(--text);-webkit-font-smoothing:antialiased}
.material-symbols-outlined{font-variation-settings:'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24;line-height:1}
img{display:block;max-width:100%}
`;

function page(w, h, body, extra = "") {
  return `<!doctype html><html><head><meta charset="utf-8">${FONTS}<style>${THEME}
  html,body{width:${w}px;height:${h}px;overflow:hidden}
  ${extra}</style></head><body>${body}</body></html>`;
}

/* ---------- shared app-screen fragments (rendered inside a device) ---------- */
function screenDashboard() {
  return `
  <div class="scr">
    <div class="topbar"><div class="ws">Cairo Co. <span class="material-symbols-outlined">expand_more</span></div><span class="material-symbols-outlined muted">notifications</span></div>
    <div class="pill"><span class="material-symbols-outlined">work</span> Villa October</div>
    <div class="net">
      <div class="nl">Net this month</div>
      <div class="nv"><span class="material-symbols-outlined up">trending_up</span>918,000<span class="cur">EGP</span></div>
      <div class="nsplit"><div class="sp in"><span>Income</span><b>1,250,000</b></div><div class="sp out"><span>Expenses</span><b>332,000</b></div></div>
    </div>
    <div class="statrow"><div class="st"><span class="material-symbols-outlined">apartment</span><small>Active projects</small><b>3</b></div><div class="st"><span class="material-symbols-outlined">savings</span><small>Budget health</small><b>Healthy</b></div></div>
    <div class="rh">Recent</div>
    ${row("in","south_west","Owner deposit","Villa October · Bank","+800,000")}
    ${row("out","north_east","El-Nasr Supplies","Materials · Unpaid","−145,000")}
    ${row("out","engineering","Worker wages","Site crew · 3 weeks","−62,000")}
    ${row("in","account_balance","Progress payment","Tower B · Bank","+500,000")}
    ${nav(0)}
  </div>`;
}
function row(kind, icon, title, sub, amt) {
  return `<div class="mrow"><div class="mic ${kind}"><span class="material-symbols-outlined">${icon}</span></div><div class="mb"><b>${title}</b><small>${sub}</small></div><div class="ma ${kind}">${amt}<small>EGP</small></div></div>`;
}
function nav(active) {
  const ic = ["home", "apartment", "receipt_long", "menu"];
  const cells = ic
    .map((n, i) => {
      const cls = i === active ? "an active" : "an";
      if (i === 2)
        return `<span class="fab material-symbols-outlined">add</span><span class="${cls} material-symbols-outlined">${n}</span>`;
      return `<span class="${cls} material-symbols-outlined">${n}</span>`;
    })
    .join("");
  return `<div class="anav">${cells}</div>`;
}
function screenVoice() {
  return `
  <div class="scr center">
    <div class="vtitle">Recording…</div>
    <div class="vmic"><span class="material-symbols-outlined">mic</span><span class="ring"></span></div>
    <div class="vt">"Forty-five thousand for materials from El-Nasr, unpaid, on Villa October"</div>
    <div class="vchips">
      <div class="vc"><small>AMOUNT</small><b>45,000 EGP</b></div>
      <div class="vc"><small>CATEGORY</small><b>Materials</b></div>
      <div class="vc"><small>SUPPLIER</small><b>El-Nasr</b></div>
      <div class="vc"><small>STATUS</small><b class="warn">Unpaid</b></div>
      <div class="vc"><small>PROJECT</small><b>Villa October</b></div>
    </div>
    <div class="vbtn"><span class="material-symbols-outlined">check</span> Confirm &amp; save</div>
    ${nav(2)}
  </div>`;
}
function screenProjects() {
  const p = (name, client, net, cls, used) => `
    <div class="pcard">
      <div class="pc-top"><div class="pc-ic"><span class="material-symbols-outlined">apartment</span></div>
        <div class="pc-h"><b>${name}</b><small>${client}</small></div>
        <div class="pc-net ${cls}">${net}<small>EGP</small></div></div>
      <div class="bar"><i style="width:${used}%"></i></div>
      <div class="pc-foot"><span>${used}% of budget</span><span>on site</span></div>
    </div>`;
  return `
  <div class="scr">
    <div class="htitle">Projects</div>
    ${p("Villa October", "Hassan Group", "+918,000", "in", 40)}
    ${p("Tower B Renovation", "Nile Properties", "−12,000", "out", 86)}
    ${p("Warehouse Fit-out", "Delta Logistics", "+553,000", "in", 62)}
    ${p("Road Works — Ph.2", "Cairo Gov.", "+6,200", "in", 54)}
    ${nav(1)}
  </div>`;
}
function screenAdd() {
  return `
  <div class="scr">
    <div class="htitle">Add expense</div>
    <div class="amount"><small>Amount</small><div class="amt-v">145,000 <span>EGP</span></div></div>
    ${field("work", "Project", "Villa October")}
    ${field("category", "Category", "Materials")}
    ${field("payments", "Method", "Bank transfer")}
    ${field("store", "Supplier", "El-Nasr Supplies")}
    <div class="save"><span class="material-symbols-outlined">check</span> Save expense</div>
    ${nav(2)}
  </div>`;
}
function field(icon, label, val) {
  return `<div class="fld"><small>${label}</small><div class="fv"><span class="material-symbols-outlined">${icon}</span>${val}<span class="material-symbols-outlined chev">expand_more</span></div></div>`;
}
function screenActivity() {
  return `
  <div class="scr">
    <div class="htitle">Activity</div>
    <div class="search"><span class="material-symbols-outlined">search</span>Search activity</div>
    <div class="chipsrow"><span class="fchip active">All</span><span class="fchip">Income</span><span class="fchip">Expenses</span></div>
    ${row("in","south_west","Owner deposit","Villa October · Bank","+800,000")}
    ${row("out","category","El-Nasr Supplies","Materials · Unpaid","−145,000")}
    ${row("in","account_balance","Progress payment","Tower B · Bank","+500,000")}
    ${row("out","construction","Crane rental","Equipment · Paid","−38,500")}
    ${row("out","local_shipping","Material delivery","Transport · Paid","−12,500")}
    ${row("in","account_balance_wallet","Second instalment","Warehouse · Cheque","+150,000")}
    ${nav(2)}
  </div>`;
}

/* ---------- device + caption wrapper (marketing screenshot) ---------- */
const SCREEN_CSS = `
.frame{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;
  background:radial-gradient(120% 60% at 50% 0%,rgba(255,109,0,.18),transparent 60%),var(--bg);
  padding:70px 0 0;position:relative}
.frame::after{content:"";position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.03) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.03) 1px,transparent 1px);background-size:64px 64px;-webkit-mask-image:radial-gradient(ellipse 90% 50% at 50% 0,#000 40%,transparent 100%);pointer-events:none}
.cap{text-align:center;padding:0 60px 46px;position:relative;z-index:2}
.cap .kick{color:var(--accent);font-weight:800;letter-spacing:3px;font-size:26px;text-transform:uppercase}
.cap h2{font-size:58px;font-weight:900;letter-spacing:-2px;margin-top:14px;line-height:1.05}
.device{width:520px;flex:1;background:#05070a;border-radius:56px 56px 0 0;padding:16px 16px 0;border:2px solid var(--borderS);border-bottom:0;box-shadow:0 -10px 80px rgba(0,0,0,.5);position:relative;z-index:2}
.screen{width:100%;height:100%;background:var(--bg);border-radius:44px 44px 0 0;overflow:hidden;padding:34px 22px 0;position:relative}
/* app screen internals */
.scr{display:flex;flex-direction:column;gap:16px;height:100%}
.scr.center{align-items:center;text-align:center}
.topbar{display:flex;align-items:center;justify-content:space-between}
.ws{font-weight:800;font-size:24px;display:flex;align-items:center;gap:2px}
.ws .material-symbols-outlined{font-size:26px;color:var(--muted)}
.muted{color:var(--muted);font-size:28px}
.pill{align-self:flex-start;display:inline-flex;align-items:center;gap:8px;background:rgba(255,125,31,.16);color:var(--accent);font-weight:700;font-size:18px;padding:9px 16px;border-radius:999px}
.pill .material-symbols-outlined{font-size:20px}
.htitle{font-size:40px;font-weight:900;letter-spacing:-1px}
.net{background:var(--surface);border:1px solid var(--border);border-radius:28px;padding:24px}
.nl{color:var(--muted);font-size:18px;font-weight:600}
.nv{display:flex;align-items:center;gap:8px;font-size:52px;font-weight:900;letter-spacing:-2px;margin:6px 0 20px}
.nv .up{color:var(--income);font-size:40px}.nv .cur{font-size:20px;color:var(--muted);font-weight:700;margin-left:4px}
.nsplit{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.sp{border-radius:16px;padding:12px 16px}.sp span{display:block;font-size:16px;color:var(--muted)}.sp b{font-size:24px}
.sp.in{background:rgba(53,208,138,.15)}.sp.in b{color:var(--income)}
.sp.out{background:rgba(255,107,107,.15)}.sp.out b{color:var(--expense)}
.statrow{display:grid;grid-template-columns:1fr 1fr;gap:14px}
.st{background:var(--surface);border:1px solid var(--border);border-radius:22px;padding:18px}
.st .material-symbols-outlined{font-size:26px;color:var(--accent)}.st small{display:block;color:var(--muted);font-size:16px;margin:8px 0 4px}.st b{font-size:28px}
.rh{font-size:24px;font-weight:750;margin-top:4px}
.mrow{display:flex;align-items:center;gap:16px;padding:6px 0}
.mic{width:56px;height:56px;border-radius:16px;display:grid;place-items:center;flex-shrink:0}
.mic .material-symbols-outlined{font-size:28px}
.mic.in{background:rgba(53,208,138,.15);color:var(--income)}.mic.out{background:rgba(255,107,107,.15);color:var(--expense)}
.mb{flex:1;min-width:0}.mb b{display:block;font-size:22px;font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.mb small{font-size:17px;color:var(--muted)}
.ma{font-weight:750;font-size:22px;text-align:right}.ma small{display:block;font-size:14px;color:var(--faint);font-weight:500}
.ma.in{color:var(--income)}.ma.out{color:var(--expense)}
.anav{align-self:stretch;display:flex;align-items:center;justify-content:space-around;background:var(--surface);border-top:1px solid var(--border);padding:22px 0 40px;margin:auto -22px 0}
.an{color:var(--faint);font-size:38px}.an.active{color:var(--accent)}
.fab{width:72px;height:72px;border-radius:22px;background:linear-gradient(180deg,var(--accent2),var(--accent));color:var(--onacc);display:grid;place-items:center;font-size:40px;box-shadow:0 10px 26px rgba(255,109,0,.45);transform:translateY(-22px)}
/* voice */
.vtitle{font-size:30px;font-weight:800;color:var(--accent);margin-top:20px}
.vmic{position:relative;width:150px;height:150px;border-radius:999px;background:rgba(255,125,31,.16);color:var(--accent);display:grid;place-items:center;margin:36px 0}
.vmic .material-symbols-outlined{font-size:76px}
.vmic .ring{position:absolute;inset:0;border-radius:999px;border:3px solid var(--accent);opacity:.5;transform:scale(1.25)}
.vt{font-size:28px;font-style:italic;color:var(--text);max-width:520px;line-height:1.4;margin-bottom:34px}
.vchips{display:flex;flex-wrap:wrap;gap:12px;justify-content:center;margin-bottom:34px}
.vc{background:var(--surface2);border:1px solid var(--border);border-radius:16px;padding:12px 18px;text-align:left}
.vc small{display:block;font-size:14px;color:var(--faint);letter-spacing:1px}.vc b{font-size:22px}.vc b.warn{color:var(--warn)}
.vbtn,.save{margin-top:6px;background:linear-gradient(180deg,var(--accent2),var(--accent));color:var(--onacc);font-weight:800;font-size:24px;padding:22px;border-radius:18px;display:flex;align-items:center;justify-content:center;gap:10px}
.save{margin-top:auto;margin-bottom:0}
.vbtn .material-symbols-outlined,.save .material-symbols-outlined{font-size:28px}
/* projects */
.pcard{background:var(--surface);border:1px solid var(--border);border-radius:24px;padding:22px}
.pc-top{display:flex;align-items:center;gap:16px}
.pc-ic{width:56px;height:56px;border-radius:16px;background:rgba(255,125,31,.16);color:var(--accent);display:grid;place-items:center}
.pc-ic .material-symbols-outlined{font-size:30px}
.pc-h{flex:1}.pc-h b{display:block;font-size:24px}.pc-h small{color:var(--muted);font-size:17px}
.pc-net{font-weight:800;font-size:22px;text-align:right}.pc-net small{display:block;font-size:14px;color:var(--faint)}
.pc-net.in{color:var(--income)}.pc-net.out{color:var(--expense)}
.bar{height:12px;background:var(--surface3);border-radius:999px;overflow:hidden;margin:16px 0 10px}
.bar i{display:block;height:100%;background:var(--accent);border-radius:999px}
.pc-foot{display:flex;justify-content:space-between;color:var(--muted);font-size:16px}
/* add */
.amount{background:var(--surface);border:1px solid var(--border);border-radius:24px;padding:24px;text-align:center}
.amount small{color:var(--muted);font-size:18px}
.amt-v{font-size:56px;font-weight:900;letter-spacing:-2px;margin-top:6px}.amt-v span{font-size:24px;color:var(--muted)}
.fld small{color:var(--muted);font-size:18px;font-weight:600}
.fv{margin-top:8px;background:var(--surface);border:1.5px solid var(--borderS);border-radius:18px;padding:20px;font-size:22px;font-weight:650;display:flex;align-items:center;gap:12px}
.fv .material-symbols-outlined{color:var(--accent);font-size:26px}.fv .chev{margin-left:auto;color:var(--muted)}
/* activity */
.search{background:var(--surface);border:1.5px solid var(--borderS);border-radius:18px;padding:18px;color:var(--muted);font-size:20px;display:flex;align-items:center;gap:12px}
.chipsrow{display:flex;gap:12px}
.fchip{border:1.5px solid var(--border);border-radius:999px;padding:12px 22px;font-size:18px;font-weight:600}
.fchip.active{background:rgba(255,125,31,.16);border-color:var(--accent);color:var(--accent)}
`;

function screenshot(kick, title, screenHtml) {
  const body = `<div class="frame"><div class="cap"><div class="kick">${kick}</div><h2>${title}</h2></div><div class="device"><div class="screen">${screenHtml}</div></div></div>`;
  return page(1080, 1920, body, SCREEN_CSS);
}

/* ---------- app icon 512x512 ---------- */
const icon = page(
  512,
  512,
  `<div class="wrap"><img src="fg.png" alt=""></div>`,
  `.wrap{width:512px;height:512px;display:grid;place-items:center;background:#ff6d00}.wrap img{width:400px;height:400px;object-fit:contain}`
);

/* ---------- feature graphic 1024x500 ---------- */
const feature = page(
  1024,
  500,
  `<div class="fg">
    <div class="fg-left">
      <div class="fg-brand"><img src="icon.png" alt=""><span>Buildozer</span></div>
      <h1>Track every pound<br>on every site.</h1>
      <p>Voice-first money tracking for construction — real-time profit, offline-safe, Arabic + English.</p>
      <div class="fg-badges"><span><i class="material-symbols-outlined">mic</i>Voice entry</span><span><i class="material-symbols-outlined">trending_up</i>Live profit</span><span><i class="material-symbols-outlined">cloud_off</i>Offline</span></div>
    </div>
    <div class="fg-glow"></div>
  </div>`,
  `.fg{width:1024px;height:500px;position:relative;overflow:hidden;background:radial-gradient(90% 120% at 78% 20%,rgba(255,109,0,.28),transparent 55%),var(--bg);display:flex;align-items:center}
   .fg::before{content:"";position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.035) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.035) 1px,transparent 1px);background-size:52px 52px;-webkit-mask-image:radial-gradient(ellipse 70% 90% at 20% 50%,#000 30%,transparent 90%)}
   .fg-left{position:relative;z-index:2;padding:0 60px;max-width:720px}
   .fg-brand{display:flex;align-items:center;gap:14px;margin-bottom:24px}
   .fg-brand img{width:52px;height:52px;border-radius:13px}.fg-brand span{font-size:28px;font-weight:800;letter-spacing:-.5px}
   .fg h1{font-size:60px;font-weight:900;letter-spacing:-2.5px;line-height:1.02}
   .fg p{color:var(--muted);font-size:21px;margin-top:18px;max-width:560px}
   .fg-badges{display:flex;gap:24px;margin-top:26px}
   .fg-badges span{display:inline-flex;align-items:center;gap:8px;color:var(--text);font-weight:600;font-size:18px}
   .fg-badges i{color:var(--accent);font-size:22px;font-variation-settings:'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24}
   .fg-glow{position:absolute;right:-120px;top:50%;transform:translateY(-50%);width:520px;height:520px;border-radius:999px;background:radial-gradient(circle,rgba(255,109,0,.22),transparent 62%);filter:blur(10px)}`
);

/* ---------- tablet dashboard (two-column) ---------- */
function pc(name, client, net, cls, used) {
  return `<div class="pcard"><div class="pc-top"><div class="pc-ic"><span class="material-symbols-outlined">apartment</span></div><div class="pc-h"><b>${name}</b><small>${client}</small></div><div class="pc-net ${cls}">${net}<small>EGP</small></div></div><div class="bar"><i style="width:${used}%"></i></div></div>`;
}
function tabletDash() {
  return `<div class="tscr">
    <div class="ttop"><div class="ws">Cairo Co. <span class="material-symbols-outlined">expand_more</span></div><div class="pill"><span class="material-symbols-outlined">work</span> All projects</div><span class="material-symbols-outlined muted">notifications</span></div>
    <div class="tcols">
      <div class="tcol">
        <div class="net">
          <div class="nl">Net this month</div>
          <div class="nv"><span class="material-symbols-outlined up">trending_up</span>1,649,000<span class="cur">EGP</span></div>
          <div class="nsplit"><div class="sp in"><span>Income</span><b>2,500,000</b></div><div class="sp out"><span>Expenses</span><b>851,000</b></div></div>
        </div>
        <div class="statrow"><div class="st"><span class="material-symbols-outlined">apartment</span><small>Active projects</small><b>3</b></div><div class="st"><span class="material-symbols-outlined">savings</span><small>Budget health</small><b>Healthy</b></div></div>
        <div class="rh">Recent activity</div>
        ${row("in","south_west","Owner deposit","Villa October · Bank","+800,000")}
        ${row("out","category","El-Nasr Supplies","Materials · Unpaid","−145,000")}
        ${row("in","account_balance","Progress payment","Tower B · Bank","+500,000")}
        ${row("out","engineering","Worker wages","Site crew · 3 weeks","−62,000")}
        ${row("out","construction","Crane rental","Equipment · Paid","−38,500")}
      </div>
      <div class="tcol">
        <div class="rh">Projects</div>
        ${pc("Villa October","Hassan Group","+918,000","in",40)}
        ${pc("Tower B Renovation","Nile Properties","−12,000","out",86)}
        ${pc("Warehouse Fit-out","Delta Logistics","+553,000","in",62)}
        ${pc("Road Works — Ph.2","Cairo Gov.","+6,200","in",54)}
      </div>
    </div>
  </div>`;
}
function tablet(kick, title, w, h) {
  const body = `<div class="frame tframe"><div class="cap"><div class="kick">${kick}</div><h2>${title}</h2></div><div class="tdevice"><div class="tscreen">${tabletDash()}</div></div></div>`;
  const extra =
    SCREEN_CSS +
    `.tframe{padding:0;justify-content:center;gap:${Math.round(h * 0.02)}px}
     .tframe .cap{padding:0 60px}
     .tdevice{width:${Math.round(w * 0.88)}px;background:#05070a;border-radius:40px;padding:22px;border:2px solid var(--borderS);box-shadow:0 40px 120px rgba(0,0,0,.6)}
     .tscreen{width:100%;background:var(--bg);border-radius:28px;overflow:hidden;padding:40px}
     .tscr{display:flex;flex-direction:column;gap:28px}
     .ttop{display:flex;align-items:center;gap:20px}.ttop .pill{margin:0 auto 0 8px}
     .tcols{display:grid;grid-template-columns:1fr 1fr;gap:32px;align-items:start}
     .tcol{display:flex;flex-direction:column;gap:18px}
     .tcol .mrow{padding:4px 0}`;
  return page(w, h, body, extra);
}

/* ---------- write everything ---------- */
const files = {
  "icon.html": icon,
  "feature.html": feature,
  "phone-1.html": screenshot("Real-time profit", "Know your margin at a glance", screenDashboard()),
  "phone-2.html": screenshot("Signature feature", "Log expenses by voice", screenVoice()),
  "phone-3.html": screenshot("Every site, live", "All your projects in one place", screenProjects()),
  "phone-4.html": screenshot("Fast entry", "Structured in seconds", screenAdd()),
  "phone-5.html": screenshot("One money feed", "Search and filter every transaction", screenActivity()),
  "tablet7-1.html": tablet("Built for the field", "Your whole site, one screen", 1200, 1920),
  "tablet7-2.html": tablet("Real-time profit", "Projects and money, side by side", 1200, 1920),
  "tablet10-1.html": tablet("Built for the field", "Your whole site, one screen", 1600, 2560),
  "tablet10-2.html": tablet("Real-time profit", "Projects and money, side by side", 1600, 2560),
};
for (const [name, html] of Object.entries(files)) {
  fs.writeFileSync(path.join(HTML_DIR, name), html);
}
console.log("wrote", Object.keys(files).length, "html canvases to", HTML_DIR);
