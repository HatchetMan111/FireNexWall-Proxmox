import { Link, NavLink } from "react-router-dom";
import ThemeToggle from "./ThemeToggle";

export default function Header() {
  return (
    <header className="site-header">
      <div className="shell header-inner">
        <Link to="/" className="brand" aria-label="Release Notes, Startseite">
          <span className="brand-mark" aria-hidden="true">
            RN
          </span>
          <span className="brand-text">
            <strong>Release Notes</strong>
            <small>Changelog &amp; Downloads</small>
          </span>
        </Link>
        <nav className="main-nav" aria-label="Hauptnavigation">
          <NavLink
            to="/"
            end
            className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
          >
            Releases
          </NavLink>
          <NavLink
            to="/admin"
            className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
          >
            Admin
          </NavLink>
          <ThemeToggle />
        </nav>
      </div>
    </header>
  );
}
