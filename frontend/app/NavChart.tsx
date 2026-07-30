"use client";

// Lightweight, dependency-free live area chart for the agUSD price — the look yield
// dashboards (Ethena sUSDe, Pendle, Coinbase) use: a smooth line over a gradient fill,
// auto-scaled to the visible window, with a pulsing dot at the live edge. Pure inline
// SVG so it can never break the bundle.
export default function NavChart({ series }: { series: number[] }) {
  const W = 520;
  const H = 150;
  const pad = 8;
  if (series.length < 2) {
    return <div className="chart chart-empty" />;
  }

  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1; // avoid /0 on a flat series
  const n = series.length;
  const x = (i: number) => pad + (i / (n - 1)) * (W - 2 * pad);
  const y = (v: number) => pad + (1 - (v - min) / span) * (H - 2 * pad);

  // Smooth the polyline with a light Catmull-Rom → cubic-bezier pass.
  let d = `M ${x(0).toFixed(2)} ${y(series[0]).toFixed(2)}`;
  for (let i = 0; i < n - 1; i++) {
    const p0 = series[Math.max(0, i - 1)];
    const p1 = series[i];
    const p2 = series[i + 1];
    const p3 = series[Math.min(n - 1, i + 2)];
    const c1x = x(i) + (x(i + 1) - x(i - 1 < 0 ? 0 : i - 1)) / 6;
    const c1y = y(p1) + (y(p2) - y(p0)) / 6;
    const c2x = x(i + 1) - (x(i + 2 > n - 1 ? n - 1 : i + 2) - x(i)) / 6;
    const c2y = y(p2) - (y(p3) - y(p1)) / 6;
    d += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)} ${c2x.toFixed(2)} ${c2y.toFixed(2)} ${x(i + 1).toFixed(2)} ${y(p2).toFixed(2)}`;
  }
  const area = `${d} L ${x(n - 1).toFixed(2)} ${H} L ${x(0).toFixed(2)} ${H} Z`;
  const cx = x(n - 1);
  const cy = y(series[n - 1]);

  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" aria-hidden>
      <defs>
        <linearGradient id="navfill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#9fd9b8" stopOpacity="0.4" />
          <stop offset="100%" stopColor="#9fd9b8" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#navfill)" />
      <path
        d={d}
        fill="none"
        stroke="#9fd9b8"
        strokeWidth={2.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
      <circle cx={cx} cy={cy} r={7} fill="#9fd9b8" opacity={0.25}>
        <animate attributeName="r" values="4;9;4" dur="1.8s" repeatCount="indefinite" />
        <animate attributeName="opacity" values="0.4;0;0.4" dur="1.8s" repeatCount="indefinite" />
      </circle>
      <circle cx={cx} cy={cy} r={3.5} fill="#dff3e7" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}
