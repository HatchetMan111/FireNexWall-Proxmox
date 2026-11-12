import { BrowserRouter, Route, Routes } from "react-router-dom";
import Header from "./components/Header";
import AdminPage from "./pages/AdminPage";
import HomePage from "./pages/HomePage";
import NotFound from "./pages/NotFound";
import ReleasePage from "./pages/ReleasePage";

export default function App() {
  return (
    <BrowserRouter>
      <a className="skip-link" href="#main">
        Zum Inhalt springen
      </a>
      <Header />
      <main id="main" className="shell main">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/release/:slug" element={<ReleasePage />} />
          <Route path="/admin" element={<AdminPage />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </main>
      <footer className="site-footer">
        <div className="shell footer-inner">
          <span>Release Notes Portal</span>
          <span>Lokal gehostet · {new Date().getFullYear()}</span>
        </div>
      </footer>
    </BrowserRouter>
  );
}
