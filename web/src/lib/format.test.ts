import { describe, expect, it } from "vitest";

import { formatDate, statusLabels } from "./format";

describe("formatDate", () => {
  it("formatiert ISO-Daten auf Deutsch", () => {
    expect(formatDate("2026-11-12")).toBe("12. November 2026");
  });

  it("gibt ungueltige Werte unveraendert zurueck", () => {
    expect(formatDate("kein-datum")).toBe("kein-datum");
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
