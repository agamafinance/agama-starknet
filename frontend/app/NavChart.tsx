"use client";
import { useState } from "react";
import { amountStr, blendedAprPct, projectNav, sharePriceStr, type VaultState } from "../lib/agama";

// Price-per-share chart in the style of yield-vault dashboards (Rocket Pool rETH,
// Ethena): a "Price per share" header, a range selector, the big current value with a
// dimmed trailing tail, and an area chart with a dashed y-grid (price levels), dated
// x-axis, and a glowing line. Dependency-free inline SVG so it can never break the bundle.

type Range = "Live" | "30D" | "90D" | "1Y";
const RANGES: Range[] = ["Live", "30D", "90D", "1Y"];
const DAY = 86400;

function niceNum(range: number, round: boolean): number {
  const exp = Math.floor(Math.log10(range || 1));
  const f = (range || 1) / Math.pow(10, exp);
  let nf: number;
  if (round) nf = f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10;
  else nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10;
  return nf * Math.pow(10, exp);
}

function niceTicks(min: number, max: number, count = 5) {
  if (max - min < 1e-12) {
    const c = min || 1;
    return { ticks: [c * 0.9995, c, c * 1.0005], lo: c * 0.999, hi: c * 1.001, dp: 6 };
  }
  const step = niceNum((max - min) / (count - 1), true);
  const lo = Math.floor(min / step) * step;
  const hi = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let v = lo; v <= hi + step / 2; v += step) ticks.push(Number(v.toFixed(10)));
  const dp = Math.max(0, Math.min(7, -Math.floor(Math.log10(step)) + 1));
  return { ticks, lo, hi, dp };
}

function fmtDate(tsSec: number): string {
  return new Date(tsSec * 1000).toLocaleDateString(undefined, { day: "numeric", month: "short" });
}
function fmtClock(tsSec: number): string {
  return new Date(tsSec * 1000).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

export default function NavChart({
  vault,
  now,
  live,
}: {
  vault: VaultState | null;
  now: number;
  live: number[];
}) {
  const [range, setRange] = useState<Range>("90D");

  const price = vault ? sharePriceStr(vault, BigInt(now), 8) : "1.00000000";
  const nav = vault ? projectNav(vault, BigInt(now)) : 0n;

  // Build the plotted series + x tick timestamps for the active range.
  let vals: number[] = [];
  let xTimes: number[] = [];
  let forecast = false;
  if (range === "Live") {
    vals = live.length >= 2 ? live : [parseFloat(price), parseFloat(price)];
    const span = vals.length;
    xTimes = vals.map((_, i) => now - (span - 1) + i);
  } else if (vault) {
    forecast = true;
    const horizon = (range === "30D" ? 30 : range === "90D" ? 90 : 365) * DAY;
    const N = 120;
    for (let k = 0; k <= N; k++) {
      const t = now + Math.round((k * horizon) / N);
      vals.push(parseFloat(sharePriceStr(vault, BigInt(t), 8)));
      xTimes.push(t);
    }
  } else {
    vals = [1, 1];
    xTimes = [now, now];
  }

  // Geometry.
  const W = 560;
  const H = 300;
  const L = 74;
  const R = 546;
  const T = 16;
  const B = 250;
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const { ticks, lo, hi, dp } = niceTicks(min, max, 5);
  const xAt = (i: number) => L + (i / (vals.length - 1)) * (R - L);
  const yAt = (v: number) => B - ((v - lo) / (hi - lo || 1)) * (B - T);

  let line = `M ${xAt(0).toFixed(2)} ${yAt(vals[0]).toFixed(2)}`;
  for (let i = 1; i < vals.length; i++) line += ` L ${xAt(i).toFixed(2)} ${yAt(vals[i]).toFixed(2)}`;
  const area = `${line} L ${xAt(vals.length - 1).toFixed(2)} ${B} L ${xAt(0).toFixed(2)} ${B} Z`;

  // x labels: 4 evenly spaced.
  const xIdx = [0, Math.round((vals.length - 1) / 3), Math.round((2 * (vals.length - 1)) / 3), vals.length - 1];
  const xLabels = xIdx.map((i, k) => ({
    x: xAt(i),
    text: forecast ? fmtDate(xTimes[i]) : fmtClock(xTimes[i]),
    anchor: (k === 0 ? "start" : k === xIdx.length - 1 ? "end" : "middle") as
      | "start"
      | "middle"
      | "end",
  }));

  // Split the price into bright head + dimmed tail (last 4 digits), Rocket-Pool style.
  const tail = 4;
  const head = price.slice(0, Math.max(0, price.length - tail));
  const dim = price.slice(Math.max(0, price.length - tail));

  return (
    <div className="card chart-card">
      <div className="chart-head">
        <span className="chart-pill">Price per share</span>
        <div className="range">
          {RANGES.map((r) => (
            <button
              key={r}
              className={r === range ? "range-btn on" : "range-btn"}
              onClick={() => setRange(r)}
            >
              {r}
            </button>
          ))}
        </div>
      </div>

      <div className="chart-id">
        <div className="chart-ticker">1 agUSD</div>
        <div className="chart-price">
          {head}
          <span className="dim">{dim}</span>
          <span className="chart-price-unit"> USDC</span>
        </div>
        <div className="chart-sub">
          NAV ${amountStr(nav, 6)} · {vault ? blendedAprPct(vault, nav) : "0.00"}% APR ·{" "}
          {forecast ? `${range} forecast` : "live"}
        </div>
      </div>

      <svg className="chart-svg" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id="navfill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#9fd9b8" stopOpacity="0.45" />
            <stop offset="100%" stopColor="#9fd9b8" stopOpacity="0.02" />
          </linearGradient>
          <filter id="glow" x="-20%" y="-40%" width="140%" height="180%">
            <feGaussianBlur stdDeviation="3.2" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* dashed y-grid + price labels */}
        {ticks.map((tk, i) => {
          const y = yAt(tk);
          if (y < T - 1 || y > B + 1) return null;
          return (
            <g key={i}>
              <line x1={L} y1={y} x2={R} y2={y} className="grid" />
              <text x={L - 8} y={y + 3.5} className="ylab" textAnchor="end">
                {tk.toFixed(dp)}
              </text>
            </g>
          );
        })}

        {/* x labels */}
        {xLabels.map((xl, i) => (
          <text key={i} x={xl.x} y={B + 20} className="xlab" textAnchor={xl.anchor}>
            {xl.text}
          </text>
        ))}

        <path d={area} fill="url(#navfill)" />
        <path
          d={line}
          fill="none"
          stroke="#c9f0d9"
          strokeWidth={2}
          strokeLinejoin="round"
          filter="url(#glow)"
          vectorEffect="non-scaling-stroke"
        />
        <circle cx={xAt(vals.length - 1)} cy={yAt(vals[vals.length - 1])} r={6} fill="#9fd9b8" opacity={0.3}>
          <animate attributeName="r" values="4;9;4" dur="1.8s" repeatCount="indefinite" />
          <animate attributeName="opacity" values="0.5;0;0.5" dur="1.8s" repeatCount="indefinite" />
        </circle>
        <circle cx={xAt(vals.length - 1)} cy={yAt(vals[vals.length - 1])} r={3} fill="#eafaf1" />
      </svg>
    </div>
  );
}
