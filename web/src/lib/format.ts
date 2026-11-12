import type { ReleaseStatus } from "./types";

const dateFormatter = new Intl.DateTimeFormat("de-DE", {
  day: "2-digit",
  month: "long",
  year: "numeric",
});

export function formatDate(value: string): string {
  const parsed = new Date(`${value}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }
  return dateFormatter.format(parsed);
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
