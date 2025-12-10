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
    resize_enabled: false,
    // Enable paste from Word plugin
    extraPlugins: 'pastefromword',
    pasteFromWordRemoveFontStyles: true,
    pasteFromWordRemoveStyles: false, // Keep some styles but clean them
    // CRITICAL: Allow all content including inline styles
    // This prevents CKEditor from stripping colors, backgrounds, etc.
    allowedContent: true,
    // Comprehensive paste filter
    on: {
      paste: function (evt) {
        const editor = evt.editor;
        let data = evt.data.dataValue;

        if (!data) return;

        console.log('Original paste:', data.substring(0, 200));

        // === STEP 1: Remove Word/Docs XML/conditional comments ===
        data = data.replace(/<!--\[if[^\]]*\]>[\s\S]*?<!\[endif\]-->/gi, '');
        data = data.replace(/<!--[\s\S]*?-->/g, '');

        // === STEP 2: Remove Office namespace tags ===
        data = data.replace(/<\/?o:p[^>]*>/gi, '');
        data = data.replace(/<\/?w:[^>]*>/gi, '');
        data = data.replace(/<\/?m:[^>]*>/gi, '');

        // === STEP 3: Remove MS Word/Docs CSS classes ===
        data = data.replace(/\s*class=["']?Mso[a-zA-Z0-9]*["']?/gi, '');
        data = data.replace(/\s*class=["']?[^"']*\bmso-[^"']*["']?/gi, '');

        // === STEP 4: Remove mso-list spans (these cause duplicate bullets) ===
        data = data.replace(/<span[^>]*mso-list[^>]*>.*?<\/span>/gi, '');
        data = data.replace(/<span[^>]*style=["'][^"']*mso-list[^"']*["'][^>]*>.*?<\/span>/gi, '');

        // === STEP 5: Clean inline bullets/numbers from list items ===
        // Match various bullet characters at start of <li>
        data = data.replace(/(<li[^>]*>)\s*[•●○◦▪▫■□✓✔➢➣➤►▶⇒→➔➜]\s*/gi, '$1');
        data = data.replace(/(<li[^>]*>)\s*[\-\*·‣⁃]\s+/gi, '$1');

        // Match numbers/letters at start of <li> (1. 1) A. a) etc.)
        data = data.replace(/(<li[^>]*>)\s*\d+[\.\)]\s*/gi, '$1');
        data = data.replace(/(<li[^>]*>)\s*[a-zA-Z][\.\)]\s*/gi, '$1');

        // === STEP 6: Remove font tags and excessive styling ===
        data = data.replace(/<\/?font[^>]*>/gi, '');
        data = data.replace(/\s*style=["'][^"']*font-family[^"']*["']/gi, '');

        // === STEP 7: Clean up empty or whitespace-only tags ===
        data = data.replace(/<p[^>]*>\s*<\/p>/gi, '');
        data = data.replace(/<span[^>]*>\s*<\/span>/gi, '');
        data = data.replace(/<div[^>]*>\s*<\/div>/gi, '');

        // === STEP 8: Remove empty class/style attributes ===
        data = data.replace(/\s*class=["']\s*["']/gi, '');
        data = data.replace(/\s*style=["']\s*["']/gi, '');

        // === STEP 9: Normalize whitespace in list items ===
        data = data.replace(/(<li[^>]*>)\s+/gi, '$1');
        data = data.replace(/\s+(<\/li>)/gi, '$1');

        console.log('Cleaned paste:', data.substring(0, 200));

        evt.data.dataValue = data;
      }
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
