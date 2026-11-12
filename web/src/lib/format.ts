import type { ReleaseStatus } from "./types";

const dateFormatter = new Intl.DateTimeFormat("de-DE", {
  day: "2-digit",
  month: "long",
  year: "numeric",
});

export function formatDate(value: string): string {
  // Backend liefert YYYY-MM-DD; falls doch ein volles ISO-Datum ankommt,
  // zerschneiden wir es auf den Datumsteil, statt es roh auszugeben.
  const parsed = new Date(`${value.slice(0, 10)}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }
  return dateFormatter.format(parsed);
}

export function todayLocal(): string {
  const now = new Date();
  const offset = now.getTimezoneOffset();
  return new Date(now.getTime() - offset * 60_000).toISOString().slice(0, 10);
}

function asciiFold(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ß/g, "ss");
}

/**
 * Spiegelt releasenotes.db.slugify: aus "1.4.0-Überarbeitung" wird
 * "1.4.0-uberarbeitung" (NFKD-Fold ohne Umlaut-Erweiterung).
 */
export function slugifyPreview(value: string): string {
  const slug = asciiFold(value.trim().toLowerCase())
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9._-]/g, "")
    .replace(/^[-._]+|[-._]+$/g, "");
  return slug || "release";
}

export const statusLabels: Record<ReleaseStatus, string> = {
  stable: "Stable",
  rc: "Release Candidate",
  beta: "Beta",
  alpha: "Alpha",
  security: "Security",
};

export const statusOrder: ReleaseStatus[] = [
  "stable",
  "rc",
  "beta",
  "alpha",
  "security",
];
