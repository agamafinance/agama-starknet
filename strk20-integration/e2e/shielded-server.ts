// Agama x STRK20 shielded web demo (local). A Node server that runs the privacy SDK
// server-side against a local devnet (real StarkWare privacy pool + mock prover) and serves
// a clickable page: shield USDC, lend into yield-bearing agUSD (encrypted note), redeem.
import http from "http";
import { Devnet } from "@starkware-libs/starknet-privacy-sdk/testing";
import { Open } from "@starkware-libs/starknet-privacy-sdk";
import { createE2eTestEnv, type E2eTestEnv } from "./src/harness.js";
import { deployAgamaStack, type AgamaAddresses } from "./src/agama-setup.js";
import { u256Calldata } from "./src/utils.js";

const PORT = 3012;
const ONE = 10n ** 18n;

let env: E2eTestEnv | null = null;
let agama: AgamaAddresses | null = null;
let ready = false;
let bootError = "";
let busy = false;
const log: string[] = [];
const push = (s: string) => {
  log.unshift(`${new Date().toISOString().slice(11, 19)}  ${s}`);
  if (log.length > 40) log.pop();
};

async function boot() {
  try {
    push("Booting local devnet + privacy pool + discovery service...");
    const devnet = new Devnet();
    env = await createE2eTestEnv(devnet, { indexer: { logFile: "web-demo-indexer.log" } });
    push("Deploying Agama stack (USDC, agUSD, vault, STRK20 anonymizer)...");
    agama = await deployAgamaStack(env.env.admin, env.env.node);
    // Give Alice a stack of USDC and let the pool pull it.
    const mint = await env.env.admin.execute({
      contractAddress: agama.usdToken,
      entrypoint: "mint",
      calldata: [env.env.alice.address, ...u256Calldata(1000n * ONE)],
    });
    await env.env.node.waitForTransaction(mint.transaction_hash);
    const approve = await env.env.alice.execute({
      contractAddress: agama.usdToken,
      entrypoint: "approve",
      calldata: [env.env.privacy.address, 1000n * ONE, 0n],
    });
    await env.env.node.waitForTransaction(approve.transaction_hash);
    ready = true;
    push("Ready. Alice funded with 1000 USDC (transparent).");
  } catch (e: any) {
    bootError = e?.message || String(e);
    push("Boot failed: " + bootError);
  }
}

async function readU256(contract: string, entrypoint: string, calldata: string[] = []) {
  const r: any = await env!.env.node.callContract({ contractAddress: contract, entrypoint, calldata });
  const a: string[] = Array.isArray(r) ? r : r.result;
  return BigInt(a[0]) + (BigInt(a[1] ?? 0) << 128n);
}

async function state() {
  if (!ready || !env || !agama) return { ready, bootError, log };
  const transparentUsdc = await readU256(agama.usdToken, "balance_of", [env.env.alice.address]);
  const { notes } = await env.transfers.alice.discoverNotes();
  const shieldedUsdc = (notes.get(BigInt(agama.usdToken)) ?? []).reduce((s, n) => s + n.amount, 0n);
  const shieldedAgusd = (notes.get(BigInt(agama.agusd)) ?? []).reduce((s, n) => s + n.amount, 0n);
  const f = (v: bigint) => (Number(v) / 1e18).toFixed(4);
  return {
    ready,
    alice: env.env.alice.address,
    transparentUsdc: f(transparentUsdc),
    shieldedUsdc: f(shieldedUsdc),
    shieldedAgusd: f(shieldedAgusd),
    log,
  };
}

async function shield(amount: bigint) {
  const { transfers, devnet } = env!;
  const { callAndProof } = await transfers.alice
    .build({ autoRegister: true, autoSetup: true, autoDiscover: { notes: "refresh", channels: "refresh" } })
    .with(agama!.usdToken, (t: any) => t.deposit({ amount }))
    .surplusTo(env!.env.alice.address)
    .execute();
  await devnet.executeOutside(callAndProof);
  await env!.indexer.waitForBlock(devnet.url);
  push(`Shielded ${(Number(amount) / 1e18).toFixed(0)} USDC into the pool (encrypted note).`);
}

async function lend(amount: bigint) {
  const { transfers, devnet } = env!;
  const { callAndProof } = await transfers.alice
    .build({ autoSetup: true, autoSelectNotes: "all", autoDiscover: { notes: "refresh", channels: "refresh" } })
    .with(agama!.usdToken)
    .withdraw({ recipient: agama!.adapter, amount })
    .surplusTo(env!.env.alice.address, false)
    .with(agama!.agusd)
    .transfer({ recipient: env!.env.alice.address, amount: Open })
    .done()
    .invoke((args: any) => {
      const openNote = args.openNotes[0];
      if (!openNote) throw new Error("no open note");
      return { contractAddress: agama!.adapter, calldata: [0n, agama!.usdToken, agama!.agusd, amount, 0n, openNote.noteId] };
    })
    .execute();
  await devnet.executeOutside(callAndProof);
  await env!.indexer.waitForBlock(devnet.url);
  push(`Lent ${(Number(amount) / 1e18).toFixed(0)}: adapter minted agUSD into a shielded note (yield-bearing).`);
}

async function redeem() {
  const { transfers, devnet } = env!;
  const { notes } = await transfers.alice.discoverNotes();
  const amount = (notes.get(BigInt(agama!.agusd)) ?? []).reduce((s: bigint, n: any) => s + n.amount, 0n);
  if (amount === 0n) {
    push("Nothing to redeem (no shielded agUSD).");
    return;
  }
  const { callAndProof } = await transfers.alice
    .build({ autoSetup: true, autoSelectNotes: "all", autoDiscover: { notes: "refresh", channels: "refresh" } })
    .with(agama!.agusd)
    .withdraw({ recipient: agama!.adapter, amount })
    .surplusTo(env!.env.alice.address, false)
    .with(agama!.usdToken)
    .transfer({ recipient: env!.env.alice.address, amount: Open })
    .done()
    .invoke((args: any) => {
      const openNote = args.openNotes[0];
      if (!openNote) throw new Error("no open note");
      return { contractAddress: agama!.adapter, calldata: [1n, agama!.agusd, agama!.usdToken, amount, 0n, openNote.noteId] };
    })
    .execute();
  await devnet.executeOutside(callAndProof);
  await env!.indexer.waitForBlock(devnet.url);
  push(`Redeemed ${(Number(amount) / 1e18).toFixed(4)} agUSD back to USDC (shielded note).`);
}

async function action(fn: () => Promise<void>) {
  if (!ready) throw new Error("not ready");
  if (busy) throw new Error("busy, wait for the previous action");
  busy = true;
  try {
    await fn();
  } finally {
    busy = false;
  }
}

const server = http.createServer(async (req, res) => {
  const url = req.url || "/";
  const send = (code: number, obj: any) => {
    res.writeHead(code, { "content-type": "application/json" });
    res.end(JSON.stringify(obj));
  };
  try {
    if (url === "/" || url.startsWith("/index")) {
      res.writeHead(200, { "content-type": "text/html" });
      res.end(HTML);
      return;
    }
    if (url === "/api/state") return send(200, await state());
    if (req.method === "POST" && url === "/api/shield") {
      await action(() => shield(100n * ONE));
      return send(200, await state());
    }
    if (req.method === "POST" && url === "/api/lend") {
      await action(() => lend(60n * ONE));
      return send(200, await state());
    }
    if (req.method === "POST" && url === "/api/redeem") {
      await action(() => redeem());
      return send(200, await state());
    }
    send(404, { error: "not found" });
  } catch (e: any) {
    push("Error: " + (e?.message || String(e)));
    send(500, { error: e?.message || String(e) });
  }
});

const HTML = `<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Agama x STRK20 shielded (local)</title><style>
:root{--bg:#254839;--panel:#2e4a3c;--border:rgba(255,255,255,.14);--text:#fff;--muted:#c2d6cb;--mint:#9fd9b8}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:"Helvetica Neue",Helvetica,Arial,sans-serif}
.wrap{max-width:620px;margin:0 auto;padding:40px 20px 80px}
.brand{font-size:13px;letter-spacing:3px;color:var(--mint);font-weight:700}
h1{font-size:30px;margin:6px 0 4px}.sub{color:var(--muted);margin:0 0 24px;font-size:14px}
.card{background:var(--panel);border:1px solid var(--border);border-radius:16px;padding:20px;margin-bottom:16px}
.row{display:flex;justify-content:space-between;align-items:center;padding:9px 0}.row+.row{border-top:1px solid var(--border)}
.muted{color:var(--muted)}.big{font-size:22px;font-weight:700;font-variant-numeric:tabular-nums}
.tag{font-size:11px;letter-spacing:.5px;text-transform:uppercase;color:var(--muted)}
.btns{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
button{flex:1;min-width:150px;padding:13px 14px;border-radius:12px;border:1px solid var(--mint);background:var(--mint);color:#173029;font-weight:700;font-size:15px;cursor:pointer}
button.ghost{background:transparent;color:var(--mint)}button:disabled{opacity:.45;cursor:not-allowed}
.shield{color:var(--mint)}.log{font-family:ui-monospace,Menlo,monospace;font-size:12px;color:var(--muted);white-space:pre-wrap;line-height:1.7;max-height:220px;overflow:auto}
.pill{display:inline-block;background:#24463a;border:1px solid var(--border);border-radius:999px;padding:3px 10px;font-size:12px;color:var(--mint)}
</style></head><body><div class="wrap">
<div class="brand">AGAMA × STARKNET</div>
<h1>Shielded vault · STRK20</h1>
<p class="sub">Local devnet with StarkWare's real privacy pool and a mock prover. Deposits are anonymized into encrypted notes. Nothing from StarkWare.</p>

<div class="card" id="status"><div class="row"><span class="muted">Booting the local privacy stack…</span></div></div>

<div class="card">
  <div class="btns">
    <button id="b-shield" onclick="act('shield')">Shield 100 USDC</button>
    <button id="b-lend" onclick="act('lend')">Lend 60 → agUSD</button>
    <button id="b-redeem" class="ghost" onclick="act('redeem')">Redeem all → USDC</button>
  </div>
</div>

<div class="card"><div class="tag" style="margin-bottom:8px">Activity</div><div class="log" id="log"></div></div>
</div>
<script>
let ready=false;
function fmtStatus(s){
  if(!s.ready) return '<div class="row"><span class="muted">Booting the local privacy stack… '+(s.bootError?('failed: '+s.bootError):'')+'</span></div>';
  return ''
    +'<div class="row"><span><span class="tag">Transparent</span><br>USDC (wallet)</span><span class="big">'+s.transparentUsdc+'</span></div>'
    +'<div class="row"><span><span class="tag">Shielded</span><br>USDC in pool <span class="pill">note</span></span><span class="big shield">'+s.shieldedUsdc+'</span></div>'
    +'<div class="row"><span><span class="tag">Shielded</span><br>agUSD (yield-bearing) <span class="pill">note</span></span><span class="big shield">'+s.shieldedAgusd+'</span></div>';
}
async function refresh(){
  const s=await (await fetch('/api/state')).json();
  ready=!!s.ready;
  document.getElementById('status').innerHTML=fmtStatus(s);
  document.getElementById('log').textContent=(s.log||[]).join('\\n');
  for(const id of ['b-shield','b-lend','b-redeem']) document.getElementById(id).disabled=!ready;
}
async function act(kind){
  for(const id of ['b-shield','b-lend','b-redeem']) document.getElementById(id).disabled=true;
  try{ await fetch('/api/'+kind,{method:'POST'}); }catch(e){}
  await refresh();
}
refresh(); setInterval(refresh, 3000);
</script></body></html>`;

boot();
server.listen(PORT, () => console.log(`shielded web demo on http://localhost:${PORT}`));
