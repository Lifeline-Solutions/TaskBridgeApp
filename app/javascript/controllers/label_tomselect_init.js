// TomSelect initialization for Jira-like label field
// Assumes @all_labels is provided in the form partial as [{id, name}]
document.addEventListener('turbo:load', function () {
  const el = document.getElementById('defect_label_ids');
  if (!el || el.tomselect) return;

  const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

  new TomSelect(el, {
    plugins: ['remove_button'],
    persist: false,
    loadThrottle: 300,
    valueField: 'id',
    labelField: 'name',
    searchField: ['name'],
    maxOptions: 100,
    preload: 'focus',
    create: function (input, callback) {
      let name = input.trim().replace(/\s+/g, '-').toLowerCase();
      if (!name) return callback();
      const exists = Object.values(this.options).some(o => o.name.toLowerCase() === name);
      if (exists) return callback();
      fetch('/labels', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
        body: JSON.stringify({ name })
      }).then(r => r.json()).then(data => {
        if (data.id) {
          callback({ id: data.id, name: data.name });
        } else { callback(); }
      }).catch(() => callback());
    },
    load: function(query, callback) {
      const url = new URL('/labels.json', window.location.origin);
      if (query) url.searchParams.set('q', query);
      url.searchParams.set('limit', '100');
      fetch(url.toString())
        .then(r => r.json())
        .then(data => callback(data))
        .catch(() => callback());
    },
    render: {
      item: function(data, escape) {
        return `<div class="ts-chip">${escape(data.name)}</div>`;
      },
      option: function(data, escape) {
        return `<div class="px-2 py-1">${escape(data.name)}</div>`;
      }
    },
    onItemAdd: function(value, item) {
      // If value looks like a raw name (not UUID) leave it; controller will create it.
    }
  });
});

// Basic styling via JS (could move to CSS)
document.addEventListener('turbo:load', () => {
  const styleId = 'tomselect-tailwind-inline';
  if (document.getElementById(styleId)) return;
  const s = document.createElement('style');
  s.id = styleId;
  s.textContent = `.ts-chip{display:inline-flex;align-items:center;background:#dbeafe;color:#1e3a8a;border-radius:0.375rem;padding:0.125rem 0.5rem;margin:0 0.25rem 0.25rem 0;font-size:0.75rem;font-weight:500}`;
  document.head.appendChild(s);
});