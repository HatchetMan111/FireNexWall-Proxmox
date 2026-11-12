import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import Markdown from "../components/Markdown";
import StatusBadge from "../components/StatusBadge";
import { ApiError, errorMessage, getRelease } from "../lib/api";
import { formatDate } from "../lib/format";
import type { Release } from "../lib/types";

export default function ReleasePage() {
  const { slug } = useParams<{ slug: string }>();
  const [release, setRelease] = useState<Release | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!slug) {
      setNotFound(true);
      setLoading(false);
      return;
    }
    let active = true;
    getRelease(slug)
      .then((item) => {
        if (active) {
          setRelease(item);
          document.title = `${item.version} · Release Notes`;
        }
      })
      .catch((err) => {
        if (!active) {
          return;
        }
        if (err instanceof ApiError && err.status === 404) {
          setNotFound(true);
        } else {
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
  }, [slug]);

  if (loading) {
    return (
      <div className="detail-layout" aria-busy="true">
        <div className="skeleton skeleton-line wide" />
        <div className="skeleton skeleton-block" />
      </div>
    );
  }

  if (notFound) {
    return (
      <div className="empty-state">
        <p className="eyebrow">404</p>
        <h1>Release nicht gefunden</h1>
        <p>Der Eintrag existiert nicht oder ist noch nicht veröffentlicht.</p>
        <Link className="button primary" to="/">
          Zurück zur Übersicht
        </Link>
      </div>
    );
  }

  if (error || !release) {
    return (
      <div className="alert error" role="alert">
        <strong>Release konnte nicht geladen werden.</strong>
        <p>{error || "Unbekannter Fehler"}</p>
      </div>
    );
  }

  return (
    <article className="release-detail">
      <Link className="back-link" to="/">
        ← Alle Releases
      </Link>
      <header className="detail-header">
        <div className="detail-meta">
          <span className="version version-large">{release.version}</span>
          <StatusBadge status={release.status} />
          <time dateTime={release.release_date}>{formatDate(release.release_date)}</time>
        </div>
        <h1>{release.title || `Release ${release.version}`}</h1>
        {release.summary ? <p className="lead">{release.summary}</p> : null}
      </header>

      {release.body_md.trim() ? (
        <section className="detail-section" aria-label="Release Notes">
          <Markdown content={release.body_md} />
        </section>
      ) : null}

      {release.known_issues_md.trim() ? (
        <section className="detail-section panel" aria-labelledby="known-issues">
          <h2 id="known-issues">Bekannte Probleme</h2>
          <Markdown content={release.known_issues_md} />
        </section>
      ) : null}

      {release.downloads.length > 0 ? (
        <section className="detail-section" aria-labelledby="downloads">
          <h2 id="downloads">Downloads</h2>
          <ul className="download-list">
            {release.downloads.map((download) => (
              <li key={`${download.label}-${download.url}`}>
                <a
                  className="download-card"
                  href={download.url}
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  <span className="download-icon" aria-hidden="true">
                    ↓
                  </span>
                  <span className="download-text">
                    <strong>{download.label}</strong>
                    {download.platform ? <small>{download.platform}</small> : null}
                    {download.sha256 ? <code>{download.sha256}</code> : null}
                  </span>
                  <span className="card-arrow" aria-hidden="true">
                    ↗
                  </span>
                </a>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </article>
  );
}
