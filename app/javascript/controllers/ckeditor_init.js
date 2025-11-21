(function () {
  // global registry for debugging
  window.CKEditors = window.CKEditors || {};

  const editorIds = ['defect_content', 'defect_content_edit'];

  // CKEditor Superbuild config with enhanced features
  const CK_CONFIG = {
    toolbar: {
      items: [
        'heading', '|',
        'fontSize', 'fontFamily', 'fontColor', 'fontBackgroundColor', '|',
        'bold', 'italic', 'underline', 'strikethrough', '|',
        'link', 'bulletedList', 'numberedList', '|',
        'alignment', 'outdent', 'indent', '|',
        'insertTable', 'blockQuote', 'code', '|',
        'undo', 'redo', 'removeFormat'
      ],
      shouldNotGroupWhenFull: true
    },
    fontSize: {
      options: [
        'tiny',
        'small',
        'default',
        'big',
        'huge'
      ]
    },
    fontFamily: {
      options: [
        'default',
        'Arial, Helvetica, sans-serif',
        'Courier New, Courier, monospace',
        'Georgia, serif',
        'Lucida Sans Unicode, Lucida Grande, sans-serif',
        'Tahoma, Geneva, sans-serif',
        'Times New Roman, Times, serif',
        'Trebuchet MS, Helvetica, sans-serif',
        'Verdana, Geneva, sans-serif'
      ]
    },
    fontColor: {
      columns: 6,
      colors: [
        { color: '#000000', label: 'Black' },
        { color: '#434343', label: 'Dark Grey' },
        { color: '#666666', label: 'Grey' },
        { color: '#999999', label: 'Light Grey' },
        { color: '#CCCCCC', label: 'Very Light Grey' },
        { color: '#FFFFFF', label: 'White', hasBorder: true },

        { color: '#E60000', label: 'Red' },
        { color: '#FF9900', label: 'Orange' },
        { color: '#FFFF00', label: 'Yellow' },
        { color: '#00FF00', label: 'Light Green' },
        { color: '#00FFFF', label: 'Cyan' },
        { color: '#0000FF', label: 'Blue' },

        { color: '#9900FF', label: 'Purple' },
        { color: '#FF00FF', label: 'Magenta' },
        { color: '#B82E00', label: 'Dark Red' },
        { color: '#006B00', label: 'Dark Green' },
        { color: '#0080C0', label: 'Dark Blue' },
        { color: '#5C00B8', label: 'Dark Purple' },

        { color: '#FFA6A6', label: 'Light Red' },
        { color: '#FFD699', label: 'Light Orange' },
        { color: '#FFFFCC', label: 'Light Yellow' },
        { color: '#CCFFCC', label: 'Pale Green' },
        { color: '#CCFFFF', label: 'Pale Cyan' },
        { color: '#CCE5FF', label: 'Light Blue' }
      ]
    },
    fontBackgroundColor: {
      columns: 6,
      colors: [
        { color: 'transparent', label: 'None' },
        { color: '#FFFFFF', label: 'White', hasBorder: true },
        { color: '#FFFFE0', label: 'Light Yellow' },
        { color: '#FFF0E0', label: 'Light Peach' },
        { color: '#FFE0E0', label: 'Light Pink' },
        { color: '#E0E0FF', label: 'Light Blue' },

        { color: '#FFFF00', label: 'Yellow Highlight' },
        { color: '#FFD700', label: 'Gold' },
        { color: '#FFA500', label: 'Orange' },
        { color: '#FF6347', label: 'Tomato' },
        { color: '#FF1493', label: 'Deep Pink' },
        { color: '#FF69B4', label: 'Hot Pink' },

        { color: '#98FB98', label: 'Pale Green' },
        { color: '#7FFFD4', label: 'Aquamarine' },
        { color: '#87CEEB', label: 'Sky Blue' },
        { color: '#DDA0DD', label: 'Plum' },
        { color: '#FFB6C1', label: 'Light Pink' },
        { color: '#CCCCCC', label: 'Light Grey' }
      ]
    },
    table: {
      contentToolbar: [
        'tableColumn', 'tableRow',
        'mergeTableCells', 'tableProperties', 'tableCellProperties'
      ],
      tableProperties: {
        borderColors: [
          { color: '#000000', label: 'Black' },
          { color: '#666666', label: 'Grey' },
          { color: '#FFFFFF', label: 'White' },
          { color: '#E60000', label: 'Red' },
          { color: '#FF9900', label: 'Orange' },
          { color: '#0000FF', label: 'Blue' }
        ],
        backgroundColors: [
          { color: 'transparent', label: 'None' },
          { color: '#FFFFFF', label: 'White' },
          { color: '#F0F0F0', label: 'Light Grey' },
          { color: '#FFFFCC', label: 'Light Yellow' },
          { color: '#CCE5FF', label: 'Light Blue' }
        ]
      },
      tableCellProperties: {
        borderColors: [
          { color: '#000000', label: 'Black' },
          { color: '#666666', label: 'Grey' },
          { color: '#FFFFFF', label: 'White' },
          { color: '#E60000', label: 'Red' },
          { color: '#FF9900', label: 'Orange' },
          { color: '#0000FF', label: 'Blue' }
        ],
        backgroundColors: [
          { color: 'transparent', label: 'None' },
          { color: '#FFFFFF', label: 'White' },
          { color: '#F0F0F0', label: 'Light Grey' },
          { color: '#FFFFCC', label: 'Light Yellow' },
          { color: '#CCE5FF', label: 'Light Blue' }
        ]
      }
    },
    alignment: {
      options: ['left', 'center', 'right', 'justify']
    },
    heading: {
      options: [
        { model: 'paragraph', title: 'Paragraph', class: 'ck-heading_paragraph' },
        { model: 'heading1', view: 'h1', title: 'Heading 1', class: 'ck-heading_heading1' },
        { model: 'heading2', view: 'h2', title: 'Heading 2', class: 'ck-heading_heading2' },
        { model: 'heading3', view: 'h3', title: 'Heading 3', class: 'ck-heading_heading3' },
        { model: 'heading4', view: 'h4', title: 'Heading 4', class: 'ck-heading_heading4' }
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
      return;
    }
    // If in the middle of initializing, bail out (prevents race)
    if (isInitializing(el)) {
      return;
    }

    // mark initializing *before* creating to prevent double-create race
    markInitializing(el);

    // Use CKEDITOR.ClassicEditor for superbuild, fallback to ClassicEditor for classic build
    const EditorConstructor = (typeof CKEDITOR !== 'undefined' && CKEDITOR.ClassicEditor)
      ? CKEDITOR.ClassicEditor
      : (typeof ClassicEditor !== 'undefined' ? ClassicEditor : null);

    if (!EditorConstructor) {
      console.error('CKEditor not loaded');
      unmarkInitializing(el);
      return;
    }

    EditorConstructor.create(el, CK_CONFIG)
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
                // Check if draft button was clicked (has formnovalidate attribute)
                const submitter = e.submitter;
                const isDraftButton = submitter && (
                  submitter.hasAttribute('formnovalidate') ||
                  submitter.value === 'draft'
                );

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
  document.addEventListener('turbo:before-cache', () => {
    editorIds.forEach(id => {
      const el = document.getElementById(id);
      if (el) {
        const editor = el._ckeditorInstance;
        if (editor) {
          editor.destroy().catch(() => { });
          delete el._ckeditorInstance;
        }
        unmarkInitialized(el);
        unmarkInitializing(el);
        if (window.CKEditors && window.CKEditors[id]) delete window.CKEditors[id];
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
