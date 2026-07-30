"use client";
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div className="wrap">
      <div className="brand">AGAMA × STARKNET</div>
      <h1>Something went wrong</h1>
      <div className="card">
        <div className="status">{error?.message || "Unknown error"}</div>
      </div>
      <button className="connect" onClick={reset}>
        Retry
      </button>
    </div>
  );
}
