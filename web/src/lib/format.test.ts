import { describe, expect, it } from "vitest";

import { formatDate, slugifyPreview, statusLabels, todayLocal } from "./format";

describe("formatDate", () => {
  it("formatiert ISO-Daten auf Deutsch", () => {
    expect(formatDate("2026-11-12")).toBe("12. November 2026");
  });

  it("schneidet Zeitanteile ab statt roh auszugeben", () => {
    expect(formatDate("2026-11-12T14:30:00")).toBe("12. November 2026");
  });

  it("gibt ungueltige Werte unveraendert zurueck", () => {
    expect(formatDate("kein-datum")).toBe("kein-datum");
  });
});

describe("todayLocal", () => {
  it("liefert ein lokales Datum im ISO-Format", () => {
    expect(todayLocal()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

describe("slugifyPreview", () => {
  it("spiegelt das Backend-Slugify inklusive Unicode-Fold", () => {
    expect(slugifyPreview("1.4.0")).toBe("1.4.0");
    expect(slugifyPreview("1.4.0-Überarbeitung")).toBe("1.4.0-uberarbeitung");
    expect(slugifyPreview("Straße 2")).toBe("strasse-2");
    expect(slugifyPreview("  Neues Release!  ")).toBe("neues-release");
    expect(slugifyPreview("Версия 1.0")).toBe("1.0");
    expect(slugifyPreview("---")).toBe("release");
  });
});

describe("statusLabels", () => {
  it("kennt alle API-Status", () => {
    expect(Object.keys(statusLabels).sort()).toEqual([
      "alpha",
      "beta",
      "rc",
      "security",
      "stable",
    ]);
  });
});
