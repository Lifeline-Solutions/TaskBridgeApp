(function () {
  // global registry for debugging
  window.CKEditors = window.CKEditors || {};

  const editorIds = ['defect_content', 'defect_content_edit'];

  // CKEditor 4 config with color support
  const CK4_CONFIG = {
    toolbar: [
      { name: 'styles', items: ['Format', 'Font', 'FontSize'] },
      { name: 'basicstyles', items: ['Bold', 'Italic', 'Underline', 'Strike'] },
      { name: 'colors', items: ['TextColor', 'BGColor'] },
      { name: 'paragraph', items: ['NumberedList', 'BulletedList', '-', 'Outdent', 'Indent', '-', 'Blockquote'] },
      { name: 'links', items: ['Link', 'Unlink'] },
      { name: 'insert', items: ['Table', 'HorizontalRule', 'SpecialChar'] },
      { name: 'tools', items: ['Maximize'] },
      { name: 'editing', items: ['Undo', 'Redo'] }
    ],
    height: 250,
    // Color palette with the same colors as Trix
    colorButton_colors: 'E60000,FF9900,FFFF00,00FF00,00FFFF,0000FF,9900FF,FF00FF,' +
      '000000,434343,666666,999999,CCCCCC,FFFFFF,' +
      'B82E00,006B00,0080C0,5C00B8,' +
      'FFA6A6,FFD699,FFFFCC,CCFFCC,CCFFFF,CCE5FF',
    colorButton_enableMore: true,
    colorButton_enableAutomatic: true,
    removePlugins: 'elementspath',
    resize_enabled: false
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
      // CKEditor 4 uses destroy() method
      editor.destroy();
    } catch (err) {
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
      return;
    }
    // If in the middle of initializing, bail out (prevents race)
    if (isInitializing(el)) {
      return;
    }

    // mark initializing *before* creating to prevent double-create race
    markInitializing(el);

    // CKEditor 4 uses CKEDITOR.replace()
    if (typeof CKEDITOR === 'undefined') {
      console.error('CKEditor 4 not loaded');
      unmarkInitializing(el);
      return;
    }

    try {
      const editor = CKEDITOR.replace(el, CK4_CONFIG);

      // attach and expose for debug/use
      el._ckeditorInstance = editor;
      markInitialized(el);
      unmarkInitializing(el);
      window.CKEditors = window.CKEditors || {};
      window.CKEditors[id] = editor;

      // keep textarea value in sync on form submit
      const form = el.closest('form');
      const errorEl = document.getElementById(`${id}_error`);
      if (form && !form._ckeditorSubmitAttached) {
        form.addEventListener('submit', (e) => {
          try {
            // Check if draft button was clicked
            const submitter = e.submitter;
            const isDraftButton = submitter && (
              submitter.hasAttribute('formnovalidate') ||
              submitter.value === 'draft'
            );

            // Update the textarea value
            el.value = editor.getData();

            // Skip validation if saving as draft
            if (isDraftButton) {
              if (errorEl) errorEl.classList.add('hidden');
              return;
            }

            // Normal validation for Create/Update buttons
            const textContent = editor.getData().replace(/<[^>]*>/g, '').trim();
            if (!textContent) {
              e.preventDefault();
              if (errorEl) errorEl.classList.remove('hidden');
              editor.focus();
            } else if (errorEl) {
              errorEl.classList.add('hidden');
            }
          } catch (err) {
            console.error('CKEditor submit error:', err);
          }
        });
        form._ckeditorSubmitAttached = true;
      }
    } catch (err) {
      unmarkInitializing(el);
      console.error('CKEditor 4 init failed for', id, err);
    }
  }

  function initializeAllEditors() {
    editorIds.forEach(id => {
      const el = document.getElementById(id);
      if (el) initEditorFor(el, id);
    });
  }

  // Destroy editors before Turbo caches the page / frame.
  document.addEventListener('turbo:before-cache', () => {
    editorIds.forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        destroyEditorForElement(el);
      }
    });
  });

  // Hook into common events
  ['DOMContentLoaded', 'turbo:load', 'turbo:frame-load'].forEach(evt =>
    document.addEventListener(evt, initializeAllEditors)
  );

  // Expose helpers for debugging
  window.__CK_destroyAll = async function () {
    for (const id of editorIds) {
      const el = document.getElementById(id);
      if (el) await destroyEditorForElement(el);
    }
  };

})();
