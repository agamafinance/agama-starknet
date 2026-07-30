// Minimal, dependency-free Starknet wallet connector.
// Talks directly to the injected Starknet Window Object (Ready / Braavos),
// which is exactly what wallet-kit libraries do under the hood — but without
// their bundle, which broke under Next's minifier (duplicate-identifier chunk).

export type StarknetWindowObject = any;

// Discover every injected wallet (window.starknet_argentX, window.starknet_braavos, …).
export function detectWallets(): StarknetWindowObject[] {
  if (typeof window === "undefined") return [];
  const w = window as any;
  const seen = new Set<string>();
  const list: StarknetWindowObject[] = [];
  for (const key of Object.keys(w)) {
    if (!key.startsWith("starknet")) continue;
    const obj = w[key];
    if (obj && typeof obj === "object" && (obj.enable || obj.request) && obj.id) {
      const id = String(obj.id);
      if (!seen.has(id)) {
        seen.add(id);
        list.push(obj);
      }
    }
  }
  return list;
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
