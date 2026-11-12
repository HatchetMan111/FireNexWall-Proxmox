import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import LoginForm from "../components/LoginForm";
import Markdown from "../components/Markdown";
import StatusBadge from "../components/StatusBadge";
import {
  ApiError,
  createRelease,
  deleteRelease,
  errorMessage,
  getSession,
  listAdminReleases,
  logout,
  updateRelease,
} from "../lib/api";
import { formatDate, statusLabels, statusOrder } from "../lib/format";
import type { DownloadLink, Release, ReleaseInput, ReleaseStatus, Session } from "../lib/types";

const today = () => new Date().toISOString().slice(0, 10);

function emptyForm(): ReleaseInput {
  return {
    version: "",
    slug: "",
    title: "",
    status: "stable",
    release_date: today(),
    summary: "",
    body_md: "",
    known_issues_md: "",
    downloads: [],
    published: true,
  };
}

function toInput(release: Release): ReleaseInput {
  return {
    version: release.version,
    slug: release.slug,
    title: release.title,
    status: release.status,
    release_date: release.release_date,
    summary: release.summary,
    body_md: release.body_md,
    known_issues_md: release.known_issues_md,
    downloads: release.downloads,
    published: release.published,
  };
}

export default function AdminPage() {
  const [session, setSession] = useState<Session | null>(null);
  const [releases, setReleases] = useState<Release[]>([]);
  const [selected, setSelected] = useState<number | "new" | null>(null);
  const [form, setForm] = useState<ReleaseInput>(emptyForm);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    document.title = "Admin · Release Notes";
    getSession()
      .then(setSession)
      .catch(() => setSession({ authenticated: false, username: null }));
  }, []);

  useEffect(() => {
    if (session?.authenticated) {
      void load();
    }
  }, [session]);

  async function load(preferred?: number | "new") {
    setLoading(true);
    setError("");
    try {
      const items = await listAdminReleases();
      setReleases(items);
      if (preferred === "new") {
        setSelected("new");
        setForm(emptyForm());
        return;
      }
      const target =
        typeof preferred === "number"
          ? items.find((item) => item.id === preferred)
          : items[0];
      if (target) {
        setSelected(target.id);
        setForm(toInput(target));
      } else {
        setSelected("new");
        setForm(emptyForm());
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setSession({ authenticated: false, username: null });
      }
      setError(errorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  function patch(values: Partial<ReleaseInput>) {
    setForm((current) => ({ ...current, ...values }));
  }

  function startNew() {
    setSelected("new");
    setForm(emptyForm());
    setError("");
    setNotice("");
  }

  function select(release: Release) {
    setSelected(release.id);
    setForm(toInput(release));
    setError("");
    setNotice("");
  }

  function updateDownload(index: number, values: Partial<DownloadLink>) {
    setForm((current) => ({
      ...current,
      downloads: current.downloads.map((item, itemIndex) =>
        itemIndex === index ? { ...item, ...values } : item
      ),
    }));
  }

  function addDownload() {
    setForm((current) => ({
      ...current,
      downloads: [
        ...current.downloads,
        { label: "", url: "https://", platform: "", sha256: "" },
      ],
    }));
  }

  function removeDownload(index: number) {
    setForm((current) => ({
      ...current,
      downloads: current.downloads.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    setNotice("");
    const payload: ReleaseInput = {
      ...form,
      slug: form.slug?.trim() ? form.slug.trim() : undefined,
      downloads: form.downloads.filter(
        (download) => download.label.trim() !== "" && download.url.trim() !== ""
      ),
    };
    try {
      const saved =
        selected === "new" || selected === null
          ? await createRelease(payload)
          : await updateRelease(selected, payload);
      setNotice("Release gespeichert.");
      await load(saved.id);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setSession({ authenticated: false, username: null });
      }
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    if (typeof selected !== "number") {
      return;
    }
    const current = releases.find((item) => item.id === selected);
    const label = current ? `${current.version} – ${current.title}` : "dieses Release";
    if (!window.confirm(`${label} wirklich löschen?`)) {
      return;
    }
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await deleteRelease(selected);
      setNotice("Release gelöscht.");
      await load();
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setSession({ authenticated: false, username: null });
      }
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function handleLogout() {
    try {
      await logout();
    } finally {
      setReleases([]);
      setSelected(null);
      setSession({ authenticated: false, username: null });
    }
  }

  if (session === null) {
    return (
      <div className="admin-loading" aria-busy="true">
        <div className="skeleton skeleton-line wide" />
        <div className="skeleton skeleton-block" />
      </div>
    );
  }

  if (!session.authenticated) {
    return <LoginForm onSuccess={setSession} />;
  }

  return (
    <div className="admin">
      <div className="admin-topbar">
        <div>
          <p className="eyebrow">Admin</p>
          <h1>Releases verwalten</h1>
        </div>
        <div className="admin-actions">
          <span className="muted">Angemeldet als {session.username}</span>
          <button className="button" type="button" onClick={handleLogout}>
            Abmelden
          </button>
        </div>
      </div>

      {error ? (
        <div className="alert error" role="alert">
          {error}
        </div>
      ) : null}
      {notice ? (
        <div className="alert success" role="status">
          {notice}
        </div>
      ) : null}

      <div className="admin-layout">
        <aside className="admin-list" aria-label="Release-Liste">
          <button className="button primary full" type="button" onClick={startNew}>
            Neues Release
          </button>
          {loading ? <p className="muted">Lade Releases …</p> : null}
          {!loading && releases.length === 0 ? (
            <p className="muted">Noch keine Releases vorhanden.</p>
          ) : null}
          <ul>
            {releases.map((release) => (
              <li key={release.id}>
                <button
                  type="button"
                  className={selected === release.id ? "admin-item active" : "admin-item"}
                  onClick={() => select(release)}
                >
                  <span className="admin-item-top">
                    <strong>{release.version}</strong>
                    <StatusBadge status={release.status} />
                  </span>
                  <span className="admin-item-title">
                    {release.title || "Ohne Titel"}
                  </span>
                  <span className="admin-item-meta">
                    {formatDate(release.release_date)}
                    {release.published ? "" : " · Entwurf"}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </aside>

        <form className="admin-editor" onSubmit={handleSave}>
          <div className="editor-heading">
            <h2>{selected === "new" ? "Neues Release" : "Release bearbeiten"}</h2>
            <div className="editor-actions">
              {typeof selected === "number" ? (
                <button
                  className="button danger"
                  type="button"
                  onClick={handleDelete}
                  disabled={busy}
                >
                  Löschen
                </button>
              ) : null}
              <button className="button primary" type="submit" disabled={busy}>
                {busy ? "Speichern …" : "Speichern"}
              </button>
            </div>
          </div>

          <div className="form-grid">
            <div className="field">
              <label htmlFor="version">Version</label>
              <input
                id="version"
                value={form.version}
                onChange={(event) => patch({ version: event.target.value })}
                placeholder="1.4.0"
                required
              />
            </div>
            <div className="field">
              <label htmlFor="slug">Slug</label>
              <input
                id="slug"
                value={form.slug ?? ""}
                onChange={(event) => patch({ slug: event.target.value })}
                placeholder="wird aus der Version erzeugt"
              />
            </div>
            <div className="field">
              <label htmlFor="status">Status</label>
              <select
                id="status"
                value={form.status}
                onChange={(event) =>
                  patch({ status: event.target.value as ReleaseStatus })
                }
              >
                {statusOrder.map((status) => (
                  <option key={status} value={status}>
                    {statusLabels[status]}
                  </option>
                ))}
              </select>
            </div>
            <div className="field">
              <label htmlFor="release_date">Veröffentlichungsdatum</label>
              <input
                id="release_date"
                type="date"
                value={form.release_date.slice(0, 10)}
                onChange={(event) => patch({ release_date: event.target.value })}
                required
              />
            </div>
            <div className="field span-2">
              <label htmlFor="title">Titel</label>
              <input
                id="title"
                value={form.title}
                onChange={(event) => patch({ title: event.target.value })}
                placeholder="Kurzer, aussagekräftiger Titel"
              />
            </div>
            <div className="field span-2">
              <label htmlFor="summary">Zusammenfassung</label>
              <textarea
                id="summary"
                rows={3}
                value={form.summary}
                onChange={(event) => patch({ summary: event.target.value })}
                placeholder="Ein bis zwei Sätze für die Übersicht"
              />
            </div>
          </div>

          <div className="editor-split">
            <div className="field">
              <label htmlFor="body_md">Release Notes (Markdown)</label>
              <textarea
                id="body_md"
                rows={18}
                value={form.body_md}
                onChange={(event) => patch({ body_md: event.target.value })}
                placeholder={"## Highlights\n\n- Punkt eins\n- Punkt zwei"}
              />
            </div>
            <div className="preview">
              <span className="preview-label">Live-Vorschau</span>
              <Markdown content={form.body_md || "_Noch kein Inhalt._"} />
            </div>
          </div>

          <div className="field">
            <label htmlFor="known_issues_md">Bekannte Probleme (Markdown)</label>
            <textarea
              id="known_issues_md"
              rows={5}
              value={form.known_issues_md}
              onChange={(event) => patch({ known_issues_md: event.target.value })}
              placeholder="- Problem eins"
            />
          </div>

          <fieldset className="downloads-fieldset">
            <div className="fieldset-heading">
              <legend>Downloads</legend>
              <button className="button small" type="button" onClick={addDownload}>
                Zeile hinzufügen
              </button>
            </div>
            {form.downloads.length === 0 ? (
              <p className="muted">Keine Downloads hinterlegt.</p>
            ) : null}
            {form.downloads.map((download, index) => (
              <div className="download-row" key={index}>
                <input
                  aria-label={`Bezeichnung ${index + 1}`}
                  value={download.label}
                  onChange={(event) => updateDownload(index, { label: event.target.value })}
                  placeholder="Bezeichnung"
                />
                <input
                  aria-label={`URL ${index + 1}`}
                  value={download.url}
                  onChange={(event) => updateDownload(index, { url: event.target.value })}
                  placeholder="https://…"
                />
                <input
                  aria-label={`Plattform ${index + 1}`}
                  value={download.platform ?? ""}
                  onChange={(event) =>
                    updateDownload(index, { platform: event.target.value })
                  }
                  placeholder="Plattform"
                />
                <button
                  className="button small danger"
                  type="button"
                  onClick={() => removeDownload(index)}
                  aria-label={`Download ${index + 1} entfernen`}
                >
                  Entfernen
                </button>
              </div>
            ))}
          </fieldset>

          <label className="checkbox">
            <input
              type="checkbox"
              checked={form.published}
              onChange={(event) => patch({ published: event.target.checked })}
            />
            <span>Veröffentlicht (für Besucher sichtbar)</span>
          </label>
        </form>
      </div>
    </div>
  );
}
