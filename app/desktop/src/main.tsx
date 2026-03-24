import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";
import "./styles/shell.css";
import "./styles/components.css";
import "./styles/wizard.css";
import "./styles/composer.css";
import "./styles/responsive.css";
import "./styles/workbench-v2.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
