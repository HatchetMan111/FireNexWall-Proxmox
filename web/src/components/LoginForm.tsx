import { useState } from "react";
import type { FormEvent } from "react";
import { errorMessage, login } from "../lib/api";
import type { Session } from "../lib/types";

export default function LoginForm({ onSuccess }: { onSuccess: (session: Session) => void }) {
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const session = await login(username.trim(), password);
      onSuccess(session);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="login-wrap">
      <div className="login-card">
        <p className="eyebrow">Geschützter Bereich</p>
        <h1>Admin-Login</h1>
        <p className="muted">Melde dich an, um Releases anzulegen und zu bearbeiten.</p>
        <form onSubmit={handleSubmit} className="login-form">
          <label htmlFor="username">Benutzername</label>
          <input
            id="username"
            name="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            autoComplete="username"
            required
          />
          <label htmlFor="password">Passwort</label>
          <input
            id="password"
            name="password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
            required
          />
          {error ? (
            <p className="form-error" role="alert">
              {error}
            </p>
          ) : null}
          <button className="button primary" type="submit" disabled={busy}>
            {busy ? "Anmelden …" : "Anmelden"}
          </button>
        </form>
        <p className="hint">
          Das Passwort wurde bei der Installation erzeugt und kann vom Betreiber
          zurückgesetzt werden.
        </p>
      </div>
    </section>
  );
}
