import React from "react";
import ReactDOM from "react-dom/client";

import { MockApp } from "./mock/MockApp";
import "./mock/styles/mock.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <MockApp />
  </React.StrictMode>,
);
