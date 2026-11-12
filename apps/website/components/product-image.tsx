"use client";

import { useEffect, useState } from "react";
import { signedProductImage } from "@/lib/api";

interface ProductImageProps {
  path: string | null | undefined;
  alt: string;
  fallbackName?: string;
  className?: string;
  eager?: boolean;
}

export function ProductImage({ path, alt, fallbackName, className, eager }: ProductImageProps) {
  const [url, setUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(Boolean(path));

  useEffect(() => {
    let active = true;
    setUrl(null);
    setLoading(Boolean(path));
    if (!path) {
      setLoading(false);
      return;
    }
    signedProductImage(path)
      .then((next) => {
        if (active) {
          setUrl(next);
          setLoading(false);
        }
      })
      .catch(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [path]);

  if (!path) {
    return (
      <div className={`media-placeholder ${className ?? ""}`} role="img" aria-label={`${alt} — image coming soon`}>
        <span>{(fallbackName ?? "IB").slice(0, 2).toUpperCase()}</span>
      </div>
    );
  }

  if (loading) {
    return <div className={`skeleton ${className ?? ""}`} style={{ width: "100%", height: "100%" }} aria-label="Loading image" />;
  }

  if (!url) {
    return (
      <div className={`media-placeholder ${className ?? ""}`} role="img" aria-label={`${alt} — image unavailable`}>
        <span>{(fallbackName ?? "IB").slice(0, 2).toUpperCase()}</span>
      </div>
    );
  }

  return (
    // Supabase signed URLs are dynamic, so a plain img keeps the remote pattern simple.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={url} alt={alt} className={className} loading={eager ? "eager" : "lazy"} decoding="async" />
  );
}
