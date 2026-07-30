// Minimal, dependency-free Starknet wallet connector.
// Talks directly to the injected Starknet Window Object (Ready / Braavos),
// which is exactly what wallet-kit libraries do under the hood — but without
// their bundle, which broke under Next's minifier (duplicate-identifier chunk).

export type StarknetWindowObject = any;

// Known injection keys. Wallets also inject under other starknet_* keys, which
// getOwnPropertyNames() picks up below; this list is the guaranteed-probe set.
const CANDIDATE_KEYS = [
  "starknet",
  "starknet_argentX",
  "starknet_ready",
  "starknet_braavos",
  "starknet_okxwallet",
  "starknet_keplr",
  "starknet_metamask",
];

function looksLikeWallet(obj: any): boolean {
  return !!obj && typeof obj === "object" && (typeof obj.enable === "function" || typeof obj.request === "function");
}

// Discover every injected wallet. Wallets inject as NON-ENUMERABLE window
// properties, so Object.keys() misses them — use getOwnPropertyNames() plus a
// direct probe of the known keys, and dedupe by wallet id.
export function detectWallets(): StarknetWindowObject[] {
  if (typeof window === "undefined") return [];
  const w = window as any;
  const seen = new Set<string>();
  const list: StarknetWindowObject[] = [];

  const consider = (obj: any) => {
    if (!looksLikeWallet(obj)) return;
    const id = String(obj.id || obj.name || list.length);
    if (seen.has(id)) return;
    seen.add(id);
    list.push(obj);
  };

  // Non-enumerable props are visible via getOwnPropertyNames (unlike Object.keys).
  let names: string[] = [];
  try {
    names = Object.getOwnPropertyNames(w).filter((k) => k.startsWith("starknet"));
  } catch {
    /* ignore */
  }
  for (const key of names) {
    try {
      consider(w[key]);
    } catch {
      /* accessing some exotic window props can throw */
    }
  }
  // Guaranteed direct probe (also covers keys not returned above).
  for (const key of CANDIDATE_KEYS) {
    try {
      consider(w[key]);
    } catch {
      /* ignore */
    }
  }
  return list;
}

// Injection can be a touch async right after load — retry briefly.
export async function detectWalletsWithRetry(tries = 4, delayMs = 300): Promise<StarknetWindowObject[]> {
  for (let i = 0; i < tries; i++) {
    const found = detectWallets();
    if (found.length > 0) return found;
    if (i < tries - 1) await new Promise((r) => setTimeout(r, delayMs));
  }
  return [];
}

// Prompt the wallet for account access and return the connected address.
export async function connectWalletObject(
  swo: StarknetWindowObject,
): Promise<{ address: string }> {
  // Modern permission request (Ready / Braavos current versions).
  try {
    if (typeof swo.request === "function") {
      await swo.request({ type: "wallet_requestAccounts", params: { silent_mode: false } });
    }
  } catch {
    /* fall through to legacy enable() */
  }
  // Legacy enable() — populates swo.account / swo.selectedAddress.
  if (typeof swo.enable === "function") {
    try {
      await swo.enable({ starknetVersion: "v5" });
    } catch {
      await swo.enable();
    }
  }
  const address = swo.selectedAddress || swo.account?.address || "";
  return { address };
}

export function walletLabel(swo: StarknetWindowObject): string {
  return swo?.name || swo?.id || "Wallet";
}
