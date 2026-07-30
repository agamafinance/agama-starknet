"use client";
import { useCallback, useEffect, useState } from "react";
import { ADDRESSES, EXPLORER } from "../lib/config";
import {
  depositCalls,
  fromUnits,
  readU256,
  redeemCalls,
  stakeCalls,
  toUnits,
  unstakeCalls,
} from "../lib/agama";
import { connectWalletObject, detectWalletsWithRetry, walletLabel } from "../lib/wallet";

export default function Home() {
  const [wallet, setWallet] = useState<any>(null);
  const [address, setAddress] = useState<string>("");
  const [picker, setPicker] = useState<any[]>([]);
  const [bal, setBal] = useState({ usdc: 0n, agusd: 0n, sagusd: 0n });
  const [amount, setAmount] = useState("");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

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
    if (found.length === 1) {
      await doConnect(found[0]);
    } else {
      setPicker(found);
    }
  }, [doConnect]);

  const disconnectWallet = useCallback(() => {
    setWallet(null);
    setAddress("");
    setPicker([]);
    setBal({ usdc: 0n, agusd: 0n, sagusd: 0n });
  }, []);

  const refresh = useCallback(async (addr: string) => {
    if (!addr) return;
    try {
      const [usdc, agusd] = await Promise.all([
        readU256(ADDRESSES.usdc, "balanceOf", [addr]),
        readU256(ADDRESSES.agusd, "balance_of", [addr]),
      ]);
      const sagusd = ADDRESSES.sagusd ? await readU256(ADDRESSES.sagusd, "balance_of", [addr]) : 0n;
      setBal({ usdc, agusd, sagusd });
    } catch {
      /* ignore transient read errors */
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
      setStatus(`${label} sent: ${tx.transaction_hash}`);
      setTimeout(() => refresh(address), 4000);
    } catch (e: any) {
      setStatus("Error: " + (e?.message || String(e)));
    } finally {
      setBusy(false);
    }
  };

  const amt = toUnits(amount);
  return (
    <div className="wrap">
      <div className="brand">AGAMA × STARKNET</div>
      <h1>Private-credit vault</h1>
      <p className="sub">Deposit USDC to mint agUSD, then stake for real-world yield.</p>

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
            <span>{fromUnits(bal.agusd)}</span>
          </div>
          <div className="row">
            <span className="muted">sagUSD</span>
            <span>{fromUnits(bal.sagusd)}</span>
          </div>
        </div>
      )}

      <div className="card">
        <div className="label">Amount</div>
        <input
          inputMode="decimal"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />

        <div className="section-label">Vault · spends USDC / agUSD</div>
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

        <div className="section-label">Staking · spends agUSD / sagUSD</div>
        <div className="btns">
          <button
            disabled={busy || !address || amt <= 0n || amt > bal.agusd || !ADDRESSES.sagusd}
            onClick={() => send(stakeCalls(amt), "Stake")}
          >
            Stake → sagUSD
          </button>
          <button
            disabled={busy || !address || amt <= 0n || amt > bal.sagusd || !ADDRESSES.sagusd}
            onClick={() => send(unstakeCalls(amt), "Unstake")}
          >
            Unstake → agUSD
          </button>
        </div>

        {status && <div className="status">{status}</div>}
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
