(function () {
  // global registry for debugging
  window.CKEditors = window.CKEditors || {};

  const editorIds = ['defect_content', 'defect_content_edit'];

  // CKEditor config (adjust as needed)
  const CK_CONFIG = {
    toolbar: [
      'heading', '|',
      'bold', 'italic', 'underline', 'strikethrough', 'link',
      'fontColor', 'fontBackgroundColor',
      'bulletedList', 'numberedList',
      'outdent', 'indent', '|',
      'insertTable', 'blockQuote', 'code',
      'undo', 'redo', 'removeFormat'
    ],
    table: {
      contentToolbar: [
        'tableColumn', 'tableRow',
        'mergeTableCells', 'tableProperties', 'tableCellProperties'
      ]
    },
    fontColor: {
      colors: [
        { color: 'hsl(0, 0%, 0%)', label: 'Black' },
        { color: 'hsl(0, 0%, 30%)', label: 'Dim grey' },
        { color: 'hsl(0, 0%, 60%)', label: 'Grey' },
        { color: 'hsl(0, 0%, 90%)', label: 'Light grey' },
        { color: 'hsl(0, 75%, 60%)', label: 'Red' },
        { color: 'hsl(30, 75%, 60%)', label: 'Orange' },
        { color: 'hsl(60, 75%, 60%)', label: 'Yellow' },
        { color: 'hsl(120, 75%, 60%)', label: 'Green' },
        { color: 'hsl(180, 75%, 60%)', label: 'Cyan' },
        { color: 'hsl(240, 75%, 60%)', label: 'Blue' },
        { color: 'hsl(300, 75%, 60%)', label: 'Purple' }
      ]
    },
    fontBackgroundColor: {
      colors: [
        { color: 'hsl(0, 0%, 100%)', label: 'White' },
        { color: 'hsl(0, 75%, 60%)', label: 'Red' },
        { color: 'hsl(30, 75%, 60%)', label: 'Orange' },
        { color: 'hsl(60, 75%, 60%)', label: 'Yellow' },
        { color: 'hsl(120, 75%, 60%)', label: 'Green' },
        { color: 'hsl(180, 75%, 60%)', label: 'Cyan' },
        { color: 'hsl(240, 75%, 60%)', label: 'Blue' },
        { color: 'hsl(300, 75%, 60%)', label: 'Purple' }
      ]
    }
  };

  function isInitializing(el) {
    return el && el.dataset && el.dataset.ckeditorInitializing === 'true';
  }

  function isInitialized(el) {
    return el && el.dataset && el.dataset.ckeditorInitialized === 'true';
  }

  function markInitializing(el) {
    if (el) el.dataset.ckeditorInitializing = 'true';
  }

  function unmarkInitializing(el) {
    if (el) delete el.dataset.ckeditorInitializing;
  }

  function markInitialized(el) {
    if (el) el.dataset.ckeditorInitialized = 'true';
  }

  function unmarkInitialized(el) {
    if (el) delete el.dataset.ckeditorInitialized;
  }

  async function destroyEditorForElement(el) {
    if (!el) return;
    const editor = el._ckeditorInstance;
    if (!editor) return;
    try {
      // destroy editor and cleanup flags
      await editor.destroy();
    } catch (err) {
      // ignore
      console.warn('Error destroying CKEditor instance', err);
    } finally {
      delete el._ckeditorInstance;
      unmarkInitialized(el);
      unmarkInitializing(el);
      if (el.id && window.CKEditors && window.CKEditors[el.id]) {
        delete window.CKEditors[el.id];
      }
    }
  }

  function initEditorFor(el, id) {
    if (!el) return;
    // If already initialized, nothing to do
    if (isInitialized(el)) {
      // console.log(`[CK] already initialized: ${id}`);
      return;
    }
    // If in the middle of initializing, bail out (prevents race)
    if (isInitializing(el)) {
      // console.log(`[CK] already initializing: ${id}`);
      return;
    }

    // mark initializing *before* creating to prevent double-create race
    markInitializing(el);

    ClassicEditor.create(el, CK_CONFIG)
      .then(editor => {
        // attach and expose for debug/use
        el._ckeditorInstance = editor;
        markInitialized(el);
        unmarkInitializing(el);
        window.CKEditors = window.CKEditors || {};
        window.CKEditors[id] = editor;

        // keep textarea value in sync on form submit (existing behaviour)
        const form = el.closest('form');
        const errorEl = document.getElementById(`${id}_error`);
        if (form) {
          // ensure we don't attach multiple submit handlers
          if (!form._ckeditorSubmitAttached) {
            form.addEventListener('submit', (e) => {
              try {
                el.value = editor.getData();
                const textContent = editor.getData().replace(/<[^>]*>/g, '').trim();
                if (!textContent) {
                  e.preventDefault();
                  if (errorEl) errorEl.classList.remove('hidden');
                  editor.editing.view.focus();
                } else if (errorEl) {
                  errorEl.classList.add('hidden');
                }
              } catch (err) {
                // ignore
              }
            });
            form._ckeditorSubmitAttached = true;
          }
        }

        // optional debug:
        // console.log(`[CK] created editor for #${id}`, editor);
      })
      .catch(err => {
        // creation failed - clean flags so retry can happen
        unmarkInitializing(el);
        console.error('CKEditor init failed for', id, err);
      });
  }

  function initializeAllEditors() {
    editorIds.forEach(id => {
      const el = document.getElementById(id);
      if (el) initEditorFor(el, id);
    });
  }

  // Destroy editors before Turbo caches the page / frame.
  // Turbo caches the DOM and will later restore it; CKEditor instances must be destroyed.
  document.addEventListener('turbo:before-cache', () => {
    editorIds.forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        // destroy synchronously (async returns promise but we can't block)
        const editor = el._ckeditorInstance;
        if (editor) {
          // call destroy but don't await here; we still clean dataset / registry
          editor.destroy().catch(() => {});
          delete el._ckeditorInstance;
        }
        unmarkInitialized(el);
        unmarkInitializing(el);
        if (window.CKEditors && window.CKEditors[id]) delete window.CKEditors[id];
      }
    });
  });

  // Hook into common events (DOMContentLoaded for full page load,
  // turbo:load for initial visits or navigation, turbo:frame-load for frames)
  ['DOMContentLoaded', 'turbo:load', 'turbo:frame-load'].forEach(evt =>
    document.addEventListener(evt, initializeAllEditors)
  );

  // Expose helpers for debugging
  window.__CK_destroyAll = async function() {
    for (const id of editorIds) {
      const el = document.getElementById(id);
      if (el) await destroyEditorForElement(el);
    }
  };

})();
