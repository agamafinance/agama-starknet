import { join } from "path";
import { type Account, type RpcProvider } from "starknet";
import {
  repoRoot,
  artifactPair,
  declareClass,
  deployContract,
  serializeByteArray,
} from "./utils.js";

export interface AgamaAddresses {
  usdToken: string;
  agusd: string;
  vault: string;
  adapter: string;
}

// Deploy the Agama stack for the shielded e2e: USDC (open-mint TestToken), agUSD (the
// yield-bearing share token, mint/burn), the split vault, and the STRK20 invoke anonymizer.
export async function deployAgamaStack(
  admin: Account,
  provider: RpcProvider,
): Promise<AgamaAddresses> {
  const testTokenArtifact = artifactPair(
    join(repoRoot(), "e2e/contracts/test-token/target/dev"),
    "test_token",
    "TestToken",
  );
  const usdcClass = await declareClass(
    admin,
    provider,
    testTokenArtifact.classPath,
    testTokenArtifact.compiledPath,
  );
  const usdToken = await deployContract(
    admin,
    provider,
    usdcClass,
    [...serializeByteArray("TestUSD"), ...serializeByteArray("USD")] as Array<string | bigint>,
    "0x1400",
  );

  const agama = (name: string) =>
    artifactPair(join(repoRoot(), "target/dev"), "agama_shielded_anonymizer", name);

  const shareArt = agama("MockShareToken");
  const shareClass = await declareClass(admin, provider, shareArt.classPath, shareArt.compiledPath);
  const agusd = await deployContract(
    admin,
    provider,
    shareClass,
    [...serializeByteArray("Agama USD"), ...serializeByteArray("agUSD")] as Array<string | bigint>,
    "0x1401",
  );

  const vaultArt = agama("MockAgamaVault");
  const vaultClass = await declareClass(admin, provider, vaultArt.classPath, vaultArt.compiledPath);
  const vault = await deployContract(admin, provider, vaultClass, [usdToken, agusd], "0x1402");

  const adapterArt = agama("AgamaShieldedAdapter");
  const adapterClass = await declareClass(
    admin,
    provider,
    adapterArt.classPath,
    adapterArt.compiledPath,
  );
  const adapter = await deployContract(admin, provider, adapterClass, [vault], "0x1403");

  return { usdToken, agusd, vault, adapter };
}
