"use client";
import { useCallback, useEffect, useState } from "react";
import { ADDRESSES, EXPLORER } from "../lib/config";
import {
  amountStr,
  depositCalls,
  fromUnits,
  projectNav,
  projectPoolValue,
  readU256,
  readVaultState,
  redeemCalls,
  sharePriceStr,
  sharesToUsdc,
  toUnits,
  type VaultState,
} from "../lib/agama";
import { connectWalletObject, detectWalletsWithRetry, walletLabel } from "../lib/wallet";
import NavChart from "./NavChart";

export default function Home() {
  const [wallet, setWallet] = useState<any>(null);
  const [address, setAddress] = useState<string>("");
  const [picker, setPicker] = useState<any[]>([]);
  const [bal, setBal] = useState({ usdc: 0n, agusd: 0n });
  const [vault, setVault] = useState<VaultState | null>(null);
  const [now, setNow] = useState<number>(Math.floor(Date.now() / 1000));
  const [amount, setAmount] = useState("");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);
  const [txs, setTxs] = useState<{ label: string; hash: string }[]>([]);
  const [series, setSeries] = useState<number[]>([]);

  // 1s clock drives the live price projection.
  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(t);
  }, []);

  // Build the price series: seed a full window by back-projecting the exact on-chain
  // formula, then append one real sample per tick so the chart scrolls live.
  const WINDOW = 150; // points (~2.5 min at 1s)
  useEffect(() => {
    if (!vault) return;
    const price = parseFloat(sharePriceStr(vault, BigInt(now), 8));
    setSeries((s) => {
      const base =
        s.length > 0
          ? s
          : Array.from({ length: WINDOW - 1 }, (_, k) =>
              parseFloat(sharePriceStr(vault, BigInt(now - (WINDOW - 1) + k), 8)),
            );
      return [...base, price].slice(-WINDOW);
    });
  }, [now, vault]);

  const loadVault = useCallback(async () => {
    try {
      setVault(await readVaultState());
    } catch {
      /* ignore transient read errors */
    }
  }, []);

  // Load vault/pool state on mount and re-sync from chain every 30s.
  useEffect(() => {
    loadVault();
    const t = setInterval(loadVault, 30000);
    return () => clearInterval(t);
  }, [loadVault]);

  const doConnect = useCallback(async (swo: any) => {
    setPicker([]);
    setStatus("");
    try {
      const { address: addr } = await connectWalletObject(swo);
      if (!addr) {
        setStatus("Connection cancelled or no account exposed.");
        return;
      }
      setWallet(swo);
      setAddress(addr);
    } catch (e: any) {
      setStatus("Connect failed: " + (e?.message || String(e)));
    }
  }, []);

  const beginConnect = useCallback(async () => {
    setStatus("Looking for wallet…");
    const found = await detectWalletsWithRetry();
    if (found.length === 0) {
      setStatus("No Starknet wallet detected. Install Ready or Braavos, then reload.");
      return;
    }
    setStatus("");
    if (found.length === 1) await doConnect(found[0]);
    else setPicker(found);
  }, [doConnect]);

  const disconnectWallet = useCallback(() => {
    setWallet(null);
    setAddress("");
    setPicker([]);
    setBal({ usdc: 0n, agusd: 0n });
  }, []);

  const refresh = useCallback(async (addr: string) => {
    if (!addr) return;
    try {
      const [usdc, agusd] = await Promise.all([
        readU256(ADDRESSES.usdc, "balanceOf", [addr]),
        readU256(ADDRESSES.agusd, "balance_of", [addr]),
      ]);
      setBal({ usdc, agusd });
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    if (address) refresh(address);
  }, [address, refresh]);

  const send = async (calls: any[], label: string) => {
    if (!wallet?.account) {
      setStatus("Connect a wallet first");
      return;
    }
    try {
      setBusy(true);
      setStatus(`${label}…`);
      const tx = await wallet.account.execute(calls);
      setStatus(`${label} sent`);
      setTxs((t) => [{ label, hash: tx.transaction_hash }, ...t].slice(0, 8));
      setTimeout(() => {
        refresh(address);
        loadVault();
      }, 4000);
    } catch (e: any) {
      setStatus("Error: " + (e?.message || String(e)));
    } finally {
      setBusy(false);
    }
  };

  const nowB = BigInt(now);
  const nav = vault ? projectNav(vault, nowB) : 0n;
  const userValue = vault ? sharesToUsdc(bal.agusd, nav, vault.supply) : 0n;

  const amt = toUnits(amount);
  return (
    <div className="wrap">
      <div className="brand">AGAMA × STARKNET</div>
      <h1>Private-credit vault</h1>
      <p className="sub">
        Deposit USDC to mint agUSD, the yield-bearing token indexed on Agama&apos;s lending pools.
      </p>

      {/* Price-per-share chart: NAV per agUSD, rising as the pools earn. */}
      <NavChart vault={vault} now={now} live={series} />

      <div className="card">
        {address ? (
          <div className="row">
            <span className="muted">
              {address.slice(0, 6)}…{address.slice(-4)}
            </span>
            <button onClick={disconnectWallet} style={{ flex: "0 0 auto", padding: "8px 14px" }}>
              Disconnect
            </button>
          </div>
        ) : picker.length > 0 ? (
          <div className="btns" style={{ flexDirection: "column" }}>
            {picker.map((w) => (
              <button key={w.id} className="connect" onClick={() => doConnect(w)}>
                Connect {walletLabel(w)}
              </button>
            ))}
          </div>
        ) : (
          <button className="connect" onClick={beginConnect}>
            Connect wallet
          </button>
        )}
      </div>

      {address && (
        <div className="card">
          <div className="row">
            <span className="muted">USDC</span>
            <span>{fromUnits(bal.usdc)}</span>
          </div>
          <div className="row">
            <span className="muted">agUSD</span>
            <span>
              {fromUnits(bal.agusd)}
              {bal.agusd > 0n && (
                <span className="muted" style={{ fontSize: 12, marginLeft: 8 }}>
                  = {amountStr(userValue, 6)} USDC
                </span>
              )}
            </span>
          </div>
        </div>
      )}

      {/* The four lending pools behind agUSD, each accruing at its own APR. */}
      <div className="pools">
        {(vault?.pools ?? []).map((p) => (
          <div className="pool" key={p.address}>
            <div className="pool-top">
              <span className="pool-label">{p.label}</span>
              <span className="pool-apr">{(Number(p.aprBps) / 100).toFixed(0)}%</span>
            </div>
            <div className="pool-sector">{p.sector}</div>
            <div className="pool-value">{amountStr(projectPoolValue(p, nowB), 6)}</div>
            <div className="pool-sub">USDC · marked live</div>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="label">Amount</div>
        <input
          inputMode="decimal"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        <div className="btns">
          <button
            className="primary"
            disabled={busy || !address || amt <= 0n || amt > bal.usdc}
            onClick={() => send(depositCalls(amt), "Deposit")}
          >
            Deposit → agUSD
          </button>
          <button
            disabled={busy || !address || amt <= 0n || amt > bal.agusd}
            onClick={() => send(redeemCalls(amt), "Redeem")}
          >
            Redeem → USDC
          </button>
        </div>
        {status && <div className="status">{status}</div>}
      </div>

      {txs.length > 0 && (
        <div className="card">
          <div className="label">Transactions (Sepolia)</div>
          {txs.map((t) => (
            <div className="row" key={t.hash}>
              <span className="muted">{t.label}</span>
              <a href={`${EXPLORER}/tx/${t.hash}`} target="_blank" rel="noreferrer">
                {t.hash.slice(0, 8)}…{t.hash.slice(-4)} ↗
              </a>
            </div>
          ))}
          <p className="muted" style={{ fontSize: 12, margin: "10px 0 0" }}>
            Real, verifiable transactions on Starknet Sepolia. Deposits here are transparent (public
            chain). Shielded STRK20 flow runs on the privacy network (see the card below).
          </p>
        </div>
      )}

      <div className="card">
        <div className="label">Privacy · STRK20</div>
        <p className="muted" style={{ fontSize: 13, lineHeight: 1.55, margin: "0 0 8px" }}>
          Agama ships the on-chain lending leg for Starknet&apos;s native STRK20 privacy pool: an{" "}
          <a
            href={`${EXPLORER}/contract/${ADDRESSES.shieldedAdapter}`}
            target="_blank"
            rel="noreferrer"
          >
            invoke anonymizer
          </a>{" "}
          deployed and proven on Sepolia, so a shielded deposit lands directly as yield-bearing
          agUSD. Full unlinkability runs through StarkWare&apos;s proving service (Stwo); the
          deposits made directly in this dApp are transparent.
        </p>
      </div>

      <p className="status">
        Live on{" "}
        <a href={EXPLORER} target="_blank" rel="noreferrer">
          Sepolia
        </a>{" "}
        · vault {ADDRESSES.vault.slice(0, 10)}…
      </p>
    </div>
  );
}
