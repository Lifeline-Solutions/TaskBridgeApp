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
Trix.config.blockAttributes.heading1 = {
  tagName: "h1",
  terminal: true,
  breakOnReturn: true,
  style: { fontWeight: "bold", fontSize: "2em" },
};
Trix.config.blockAttributes.heading2 = {
  tagName: "h2",
  terminal: true,
  breakOnReturn: true,
  style: { fontWeight: "bold", fontSize: "1.5em" },
};
Trix.config.blockAttributes.heading3 = {
  tagName: "h3",
  terminal: true,
  breakOnReturn: true,
  style: { fontWeight: "bold", fontSize: "1.17em" },
};

// --- Tables with bold text and visible gray-900 borders ---
Trix.config.blockAttributes.borderedTable = {
  tagName: "table",
  parser(el) {
    return (
      el.tagName === "TABLE" &&
      el.style.borderCollapse === "collapse" &&
      el.style.border === "2px solid #111827"
    );
  },
  style: {
    borderCollapse: "collapse",
    border: "2px solid #111827", // Tailwind gray-900 (#111827)
    width: "100%",
  },
};

// --- Allow table and list tags in sanitizer ---
document.addEventListener("trix-before-initialize", () => {
  if (Trix.config?.sanitizer) {
    const allowedTags = ["TABLE", "TBODY", "THEAD", "TFOOT", "TR", "TD", "TH", "UL", "OL", "LI"];
    const orig = Trix.config.sanitizer.sanitizeNode;
    Trix.config.sanitizer.sanitizeNode = function(node) {
      if (allowedTags.includes(node.nodeName)) return node;
      return orig.call(this, node);
    };
  }
});

// --- Custom table styling after insertion or on change ---
function styleTablesInTrixContent(root) {
  root.querySelectorAll("table").forEach(table => {
    table.style.borderCollapse = "collapse";
    table.style.border = "2px solid #111827";
    table.style.width = "100%";
    Array.from(table.rows).forEach(row => {
      Array.from(row.cells).forEach(cell => {
        cell.style.border = "2px solid #111827";
        cell.style.fontWeight = "bold";
        cell.style.padding = "8px";
        cell.style.color = "#111827";
      });
    });
  });
}

// --- Add custom toolbar buttons ---
document.addEventListener("trix-initialize", (event) => {
  const editor = event.target;
  const toolbarElement = editor.toolbarElement;
  const textGroup = toolbarElement.querySelector(".trix-button-group--text-tools");
  const blockGroup = toolbarElement.querySelector("[data-trix-button-group='block-tools']");

  // Color + text buttons
  const buttons = [
    { name: "text-red", label: "🔴" },
    { name: "text-blue", label: "🔵" },
    { name: "text-green", label: "🟢" },
    { name: "text-yellow", label: "🟡" },
    { name: "text-purple", label: "🟣" },
    { name: "text-gray", label: "⚫" },
    { name: "text-black", label: "⬛" },
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
    blockGroup.insertAdjacentHTML(
      "beforeend",
      `<button type="button" class="trix-button" data-trix-attribute="${h}" title="Heading ${i + 1}">H${i + 1}</button>`
    );
  });

  // --- *** NEW: Add Bullet, Numbered List, and Code Block Buttons *** ---
  const blockButtons = [
    { attribute: "bullet", label: "•", title: "Bullet Points" },
    { attribute: "number", label: "1.", title: "Numbered List" },
    { attribute: "code", label: "</>", title: "Code Block" }
  ];

  blockButtons.forEach(({ attribute, label, title }) => {
    blockGroup.insertAdjacentHTML(
      "beforeend",
      `<button type="button" class="trix-button" data-trix-attribute="${attribute}" title="${title}">${label}</button>`
    );
  });


  // Table button with dialog
  const tableBtn = document.createElement("button");
  tableBtn.type = "button";
  tableBtn.className = "trix-button";
  tableBtn.title = "Insert Table";
  tableBtn.innerText = "Tbl";
  tableBtn.addEventListener("click", (e) => {
    e.preventDefault();
    showTableDialog(editor);
  });
  blockGroup.appendChild(tableBtn);
});

// --- Table dialog and insertion logic ---
function showTableDialog(editor) {
  let prevDialog = document.getElementById('trix-table-dialog');
  if (prevDialog) prevDialog.remove();

  const dialog = document.createElement('div');
  dialog.id = 'trix-table-dialog';
  Object.assign(dialog.style, {
    position: 'absolute', background: '#fff', border: '1px solid #ccc',
    padding: '12px', zIndex: 1000, boxShadow: '0 4px 24px rgba(0,0,0,0.1)'
  });

  dialog.innerHTML = `
    <label>Rows: <input type="number" id="trix-table-rows" min="1" max="20" value="2" style="width:40px;"></label>
    <label style="margin-left:10px;">Cols: <input type="number" id="trix-table-cols" min="1" max="10" value="2" style="width:40px;"></label>
    <button id="trix-table-insert" style="margin-left:10px;">Insert</button>
    <button id="trix-table-cancel" style="margin-left:5px;">Cancel</button>
  `;
  document.body.appendChild(dialog);

  const rect = editor.toolbarElement.querySelector("[title='Insert Table']").getBoundingClientRect();
  dialog.style.top = `${rect.bottom + window.scrollY + 5}px`;
  dialog.style.left = `${rect.left + window.scrollX}px`;

  dialog.querySelector('#trix-table-insert').onclick = () => {
    const rows = parseInt(dialog.querySelector('#trix-table-rows').value, 10) || 2;
    const cols = parseInt(dialog.querySelector('#trix-table-cols').value, 10) || 2;
    insertTableToTrix(editor, rows, cols);
    dialog.remove();
  };
  dialog.querySelector('#trix-table-cancel').onclick = () => dialog.remove();
}

function insertTableToTrix(editor, rows, cols) {
  let tableHTML = '<table>';
  for (let r = 0; r < rows; r++) {
    tableHTML += '<tr>';
    for (let c = 0; c < cols; c++) {
      tableHTML += `<td>${r === 0 ? `Header ${c + 1}` : "&nbsp;"}</td>`;
    }
    tableHTML += '</tr>';
  }
  tableHTML += '</table>';

  editor.editor.insertHTML(tableHTML);
  styleTablesInTrixContent(editor.editor.element);
}

// --- Ensure table and color styles persist on any change ---
document.addEventListener("trix-change", (event) => {
  if (event.target.editor) {
    styleTablesInTrixContent(event.target.editor.element);
  }
});

// --- Handle pasting Markdown/Excel tables ---
document.addEventListener("trix-paste", (event) => {
  const editor = event.target.editor;
  const pastedText = (event.clipboardData || window.clipboardData).getData("text/plain");
  const lines = pastedText.trim().split('\n');

  // Heuristic: Check for pipe-separated data in at least one line.
  if (lines.length > 0 && lines[0].includes('|')) {
    const bodyStartIndex = lines[1] && lines[1].replace(/[-|: ]/g, '') === '' ? 2 : 1;

    let tableHTML = '<table>';
    const headerCells = lines[0].split('|').map(cell => cell.trim());
    if (headerCells.some(c => c)) {
      tableHTML += '<tr>';
      headerCells.forEach(cell => { tableHTML += `<th>${cell || '&nbsp;'}</th>`; });
      tableHTML += '</tr>';
    }

    for (let i = bodyStartIndex; i < lines.length; i++) {
      const bodyCells = lines[i].split('|').map(cell => cell.trim());
      if (bodyCells.some(c => c)) {
        tableHTML += '<tr>';
        bodyCells.forEach(cell => { tableHTML += `<td>${cell || '&nbsp;'}</td>`; });
        tableHTML += '</tr>';
      }
    }
    tableHTML += '</table>';

    event.preventDefault();
    editor.insertHTML(tableHTML);
    styleTablesInTrixContent(editor.element);
  }
});