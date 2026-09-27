import { useId } from "react";

export function Logo({ size = 34 }: { size?: number }) {
  const gradient = useId();
  return <svg className="logo-mark" width={size} height={size} viewBox="0 0 40 40" aria-hidden="true">
    <defs>
      <linearGradient id={gradient} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#c4b5fd" />
        <stop offset=".5" stopColor="#7c3aed" />
        <stop offset="1" stopColor="#22d3ee" />
      </linearGradient>
    </defs>
    <rect width="40" height="40" rx="12" fill={`url(#${gradient})`} />
    <path d="M23 6.5 10.5 22.8h8.3L16.6 33.5 29.5 16.6h-8.4L23 6.5Z" fill="#0a0814" />
  </svg>;
}

export function Brand({ size }: { size?: number }) {
  return <a className="brand" href="#top" aria-label="Voltrix home">
    <Logo size={size} />
    <span>Voltrix</span>
  </a>;
}
