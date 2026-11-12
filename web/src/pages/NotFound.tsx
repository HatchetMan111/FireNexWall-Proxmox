import { Link } from "react-router-dom";

export default function NotFound() {
  return (
    <div className="empty-state">
      <p className="eyebrow">404</p>
      <h1>Seite nicht gefunden</h1>
      <p>Die angeforderte Seite existiert nicht.</p>
      <Link className="button primary" to="/">
        Zur Startseite
      </Link>
    </div>
  );
}
