import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import StatusBadge from "../components/StatusBadge";
import { errorMessage, listReleases } from "../lib/api";
import { formatDate, statusOrder } from "../lib/format";
import type { Release, ReleaseStatus } from "../lib/types";

type Filter = "all" | ReleaseStatus;

export default function HomePage() {
  const [releases, setReleases] = useState<Release[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("all");

  useEffect(() => {
    document.title = "Release Notes";
    let active = true;
    listReleases()
      .then((items) => {
        if (active) {
          setReleases(items);
          setError("");
        }
      })
      .catch((err) => {
        if (active) {
          setError(errorMessage(err));
        }
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, []);

  const latest = releases[0];
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return releases.filter((release) => {
      const matchesFilter = filter === "all" || release.status === filter;
      const haystack = `${release.version} ${release.title} ${release.summary}`.toLowerCase();
      return matchesFilter && (needle === "" || haystack.includes(needle));
    });
  }, [releases, query, filter]);

  const availableStatuses = useMemo(
    () => statusOrder.filter((status) => releases.some((release) => release.status === status)),
    [releases]
  );

  return (
    <div className="home">
      {loading ? (
        <div className="hero skeleton-hero" aria-hidden="true" />
      ) : latest ? (
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">Neueste Version</p>
            <div className="hero-version-row">
              <span className="hero-version">{latest.version}</span>
              <StatusBadge status={latest.status} />
            </div>
            <h1>{latest.title || `Release ${latest.version}`}</h1>
            {latest.summary ? <p className="hero-summary">{latest.summary}</p> : null}
            <div className="hero-actions">
              <Link className="button primary" to={`/release/${latest.slug}`}>
                Release ansehen
              </Link>
              <span className="hero-date">Veröffentlicht am {formatDate(latest.release_date)}</span>
            </div>
          </div>
          <div className="hero-panel" aria-hidden="true">
            <div className="hero-stat">
              <span className="hero-stat-value">{releases.length}</span>
              <span className="hero-stat-label">Releases im Archiv</span>
            </div>
            <div className="hero-stat">
              <span className="hero-stat-value">{latest.status.toUpperCase()}</span>
              <span className="hero-stat-label">Aktueller Kanal</span>
            </div>
            <div className="hero-lines">
              <span />
              <span />
              <span />
            </div>
          </div>
        </section>
      ) : null}

      {error ? (
        <div className="alert error" role="alert">
          <strong>Releases konnten nicht geladen werden.</strong>
          <p>{error}</p>
          <button className="button" type="button" onClick={() => window.location.reload()}>
            Erneut versuchen
          </button>
        </div>
      ) : null}

      <section className="archive" aria-labelledby="archive-title">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Archiv</p>
            <h2 id="archive-title">Alle Releases</h2>
          </div>
          <span className="result-count">
            {filtered.length} {filtered.length === 1 ? "Eintrag" : "Einträge"}
          </span>
        </div>

        <div className="toolbar">
          <div className="search-field">
            <label htmlFor="release-search" className="sr-only">
              Releases durchsuchen
            </label>
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="11" cy="11" r="7" />
              <path d="m16.5 16.5 4 4" />
            </svg>
            <input
              id="release-search"
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Version, Titel oder Stichwort suchen"
              autoComplete="off"
            />
          </div>
          <div className="filter-chips" role="group" aria-label="Nach Status filtern">
            <button
              type="button"
              className={filter === "all" ? "chip active" : "chip"}
              onClick={() => setFilter("all")}
              aria-pressed={filter === "all"}
            >
              Alle
            </button>
            {availableStatuses.map((status) => (
              <button
                key={status}
                type="button"
                className={filter === status ? "chip active" : "chip"}
                onClick={() => setFilter(status)}
                aria-pressed={filter === status}
              >
                {status}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="release-grid" aria-hidden="true">
            <div className="release-card skeleton" />
            <div className="release-card skeleton" />
            <div className="release-card skeleton" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <h3>Keine Releases gefunden</h3>
            <p>Passe Suche oder Statusfilter an.</p>
          </div>
        ) : (
          <div className="release-grid">
            {filtered.map((release) => (
              <Link className="release-card" to={`/release/${release.slug}`} key={release.id}>
                <div className="card-top">
                  <span className="version">{release.version}</span>
                  <StatusBadge status={release.status} />
                </div>
                <h3>{release.title || `Release ${release.version}`}</h3>
                {release.summary ? <p>{release.summary}</p> : null}
                <div className="card-foot">
                  <time dateTime={release.release_date}>{formatDate(release.release_date)}</time>
                  <span className="card-arrow" aria-hidden="true">
                    →
                  </span>
                </div>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
