import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

const stored = localStorage.getItem("rn-theme");
const prefersLight = window.matchMedia("(prefers-color-scheme: light)").matches;
document.documentElement.dataset.theme =
  stored === "light" || stored === "dark" ? stored : prefersLight ? "light" : "dark";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
