// --- Colors ---
const colorMap = {
  "text-red": "red",
  "text-blue": "blue",
  "text-green": "green",
  "text-yellow": "yellow",
  "text-purple": "purple",
  "text-gray": "gray",
  "text-black": "black",
};

Object.entries(colorMap).forEach(([attr, clr]) => {
  Trix.config.textAttributes[attr] = {
    style: { color: clr },
    inheritable: true,
    parser(element) { return element.style.color === clr; },
    remover(element) { if (element.style) element.style.color = ""; },
  };
});

// --- Other inline styles ---
Trix.config.textAttributes["text-underline"] = {
  style: { textDecoration: "underline" },
  inheritable: true,
  parser(el) { return /underline/.test(el.style.textDecoration); },
  remover(el) { el.style.textDecoration = ""; },
};

Trix.config.textAttributes["text-highlight"] = {
  style: { backgroundColor: "yellow" },
  inheritable: true,
  parser(el) { return el.style.backgroundColor === "yellow"; },
  remover(el) { el.style.backgroundColor = ""; },
};

Trix.config.textAttributes["text-large"] = {
  style: { fontSize: "1.5em" },
  inheritable: true,
  parser(el) { return el.style.fontSize === "1.5em"; },
  remover(el) { el.style.fontSize = ""; },
};

Trix.config.textAttributes["text-small"] = {
  style: { fontSize: "0.75em" },
  inheritable: true,
  parser(el) { return el.style.fontSize === "0.75em"; },
  remover(el) { el.style.fontSize = ""; },
};

// --- Headings ---
Trix.config.blockAttributes.heading1 = { tagName: "h1", terminal: true, breakOnReturn: true };
Trix.config.blockAttributes.heading2 = { tagName: "h2", terminal: true, breakOnReturn: true };
Trix.config.blockAttributes.heading3 = { tagName: "h3", terminal: true, breakOnReturn: true };

// --- Tables with borders ---
Trix.config.blockAttributes.borderedTable = {
  tagName: "table",
  parser(el) { return el.tagName === "TABLE" && el.style.borderCollapse === "collapse"; },
  style: { borderCollapse: "collapse", border: "1px solid #333" },
};

// --- Allow table tags in sanitizer ---
document.addEventListener("trix-before-initialize", () => {
  if (Trix.config?.sanitizer) {
    const allowedTags = ["TABLE", "TBODY", "THEAD", "TFOOT", "TR", "TD", "TH"];
    const orig = Trix.config.sanitizer.sanitizeNode;
    Trix.config.sanitizer.sanitizeNode = function(node) {
      if (allowedTags.includes(node.nodeName)) return node;
      return orig.call(this, node);
    };
  }
});

// --- Add custom toolbar buttons ---
document.addEventListener("trix-initialize", (event) => {
  const textGroup = event.target.toolbarElement.querySelector(".trix-button-group--text-tools");
  const blockGroup = event.target.toolbarElement.querySelector("[data-trix-button-group='block-tools']");

  // Color + text buttons
  const buttons = [
    { name: "text-red", label: "🔴" },
    { name: "text-blue", label: "🔵" },
    { name: "text-green", label: "🟢" },
    { name: "text-yellow", label: "🟡" },
    { name: "text-underline", label: "U̲" },
    { name: "text-highlight", label: "🖍️" },
    { name: "text-large", label: "🔠" },
    { name: "text-small", label: "🔡" },
  ];

  buttons.forEach(({ name, label }) => {
    textGroup.insertAdjacentHTML(
      "beforeend",
      `<button type="button" class="trix-button" data-trix-attribute="${name}" title="${name}">${label}</button>`
    );
  });

  // Headings
  ["heading1", "heading2", "heading3"].forEach((h, i) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "trix-button";
    btn.setAttribute("data-trix-attribute", h);
    btn.title = `Heading ${i + 1}`;
    btn.innerText = `H${i + 1}`;
    blockGroup.appendChild(btn);
  });

  // Table
  const tableBtn = document.createElement("button");
  tableBtn.type = "button";
  tableBtn.className = "trix-button";
  tableBtn.setAttribute("data-trix-attribute", "borderedTable");
  tableBtn.title = "Bordered Table";
  tableBtn.innerText = "Tbl";
  blockGroup.appendChild(tableBtn);
});
