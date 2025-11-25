(function () {
  // global registry for debugging
  window.CKEditors = window.CKEditors || {};

  const editorIds = ['defect_content', 'defect_content_edit'];

  // CKEditor 5 config
  const CK5_CONFIG = {
    toolbar: {
      items: [
        'heading', '|',
        'bold', 'italic', 'underline', 'strikethrough', '|',
        'fontColor', 'fontBackgroundColor', '|',
        'bulletedList', 'numberedList', 'outdent', 'indent', 'blockQuote', '|',
        'link', 'insertTable', 'horizontalLine', '|',
        'undo', 'redo', '|',
        'removeFormat'
      ],
      shouldNotGroupWhenFull: true
    },
    removePlugins: [
      // Disable features we don't want or that require extra config
      'CKBox', 'CKFinder', 'EasyImage', 'RealTimeCollaborativeComments',
      'RealTimeCollaborativeTrackChanges', 'RealTimeCollaborativeRevisionHistory',
      'PresenceList', 'Comments', 'TrackChanges', 'TrackChangesData', 'RevisionHistory',
      'Pagination', 'WProofreader', 'MathType', 'SlashCommand', 'Template', 'DocumentOutline',
      'FormatPainter', 'TableOfContents', 'PasteFromOfficeEnhanced'
    ]
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
      // CKEditor 5 uses destroy() which returns a promise
      await editor.destroy();
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

  async function initEditorFor(el, id) {
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

    // CKEditor 5 check
    if (typeof CKEDITOR === 'undefined' || !CKEDITOR.ClassicEditor) {
      console.error('CKEditor 5 not loaded');
      unmarkInitializing(el);
      return;
    }

    try {
      const editor = await CKEDITOR.ClassicEditor.create(el, CK5_CONFIG);

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
            const data = editor.getData();
            el.value = data;

            // Skip validation if saving as draft
            if (isDraftButton) {
              if (errorEl) errorEl.classList.add('hidden');
              return;
            }

            // Normal validation for Create/Update buttons
            const textContent = data.replace(/<[^>]*>/g, '').trim();
            if (!textContent) {
              e.preventDefault();
              if (errorEl) errorEl.classList.remove('hidden');
              // Focus editor
              editor.editing.view.focus();
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
      console.error('CKEditor 5 init failed for', id, err);
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
