// Initialize CKEditor on defect content textareas (new & edit)
document.addEventListener('turbo:load', () => {
  const ids = ['defect_content', 'defect_content_edit'];

  ids.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    if (el._ckeditorInstance) return; // already initialized

    ClassicEditor.create(el, {
      toolbar: [
        'heading', '|', 'bold', 'italic', 'underline', 'strikethrough', 'link', 'bulletedList', 'numberedList',
        'outdent', 'indent', '|', 'insertTable', 'blockQuote', 'code', 'undo', 'redo', 'removeFormat'
      ],
      table: {
        contentToolbar: ['tableColumn', 'tableRow', 'mergeTableCells', 'tableProperties', 'tableCellProperties']
      }
    }).then(editor => {
      el._ckeditorInstance = editor;
      // Optional: hook for paste normalization
      editor.plugins.get('Clipboard').on('inputTransformation', () => {
        // customize if needed
      });
      const form = el.closest('form');
      const errorEl = document.getElementById(`${id}_error`);
      if (form) {
        form.addEventListener('submit', (e) => {
          el.value = editor.getData(); // sync
          const textContent = editor.getData().replace(/<[^>]*>/g, '').trim();
            if (!textContent) {
              e.preventDefault();
              if (errorEl) errorEl.classList.remove('hidden');
              editor.editing.view.focus();
            } else if (errorEl) {
              errorEl.classList.add('hidden');
            }
        });
      }
    }).catch(err => {
      // eslint-disable-next-line no-console
      console.error('CKEditor init failed', err);
    });
  });
});