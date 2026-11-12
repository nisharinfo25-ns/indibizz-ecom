import type { ReactNode } from "react";
import { AlertIcon, PackageIcon } from "./icons";

export function EmptyState({
  title,
  description,
  action,
  icon,
}: {
  title: string;
  description: string;
  action?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="empty-state">
      <div className="empty-icon">{icon ?? <PackageIcon size={26} />}</div>
      <h3>{title}</h3>
      <p>{description}</p>
      {action}
    </div>
  );
}

export function ErrorPanel({ message, retry }: { message: string; retry?: () => void }) {
  return (
    <div className="alert error" role="alert">
      <AlertIcon size={18} />
      <div className="stack-sm" style={{ flex: 1 }}>
        <span>{message}</span>
        {retry && (
          <button type="button" className="link-btn" onClick={retry} style={{ alignSelf: "flex-start" }}>
            Try again
          </button>
        )}
      </div>
    </div>
  );
}

export function LoadingGrid({ count = 8 }: { count?: number }) {
  return (
    <div className="product-grid" aria-label="Loading products" aria-busy="true">
      {Array.from({ length: count }, (_, index) => (
        <div className="skeleton-card" key={index}>
          <div className="skeleton skeleton-media" />
          <div className="skeleton skeleton-line short" />
          <div className="skeleton skeleton-line" />
          <div className="skeleton skeleton-line short" />
        </div>
      ))}
    </div>
  );
}

export function LoadingBlock({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="loading-block" role="status">
      <span className="spinner lg" />
      <span>{label}</span>
    </div>
  );
}

export function SkeletonLines({ count = 4 }: { count?: number }) {
  return (
    <div className="stack-sm" aria-busy="true">
      {Array.from({ length: count }, (_, index) => (
        <div key={index} className={`skeleton skeleton-line ${index % 3 === 1 ? "short" : ""}`} />
      ))}
    </div>
  );
}

export function PageHead({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="section-head">
      <div>
        {eyebrow && <div className="eyebrow" style={{ marginBottom: 8 }}>{eyebrow}</div>}
        <h1 style={{ fontSize: "clamp(1.7rem, 3.6vw, 2.5rem)" }}>{title}</h1>
        {description && <p className="lead" style={{ marginTop: 8 }}>{description}</p>}
      </div>
      {action}
    </div>
  );
}
