// document.addEventListener('trix-initialize', (event) => {
//   const toolbar = event.target.toolbarElement.querySelector('.trix-button-group--text-tools');

//   const buttons = [
//     { name: 'text-red', label: '🔴' },
//     { name: 'text-blue', label: '🔵' },
//     { name: 'text-green', label: '🟢' },
//     { name: 'text-yellow', label: '🟡' },
//     { name: 'text-underline', label: 'U̲' },
//     { name: 'text-highlight', label: '🖍️' },
//     { name: 'text-large', label: '🔠' },
//     { name: 'text-small', label: '🔡' },
//   ];

//   buttons.forEach(({ name, label }) => {
//     toolbar.insertAdjacentHTML('beforeend', `
//       <button type="button" class="trix-button" data-trix-attribute="${name}" title="${name}">${label}</button>
//     `);
//   });
// });

// document.addEventListener('trix-initialize', () => {
//   const exclusiveColors = ['text-red', 'text-blue', 'text-green', 'text-yellow'];

//   exclusiveColors.forEach((color) => {
//     // eslint-disable-next-line no-undef
//     Trix.config.textAttributes[color] = {
//       style: { color: color.split('-')[1] },
//       inheritable: true,
//       parser(element) {
//         return element.style.color === color.split('-')[1];
//       },
//       remover(element) {
//         exclusiveColors.forEach((c) => element.removeAttribute(c));
//       },
//     };
//   });

//   // eslint-disable-next-line no-undef
//   Trix.config.textAttributes['text-underline'] = {
//     style: { textDecoration: 'underline' },
//     inheritable: true,
//   };

//   // eslint-disable-next-line no-undef
//   Trix.config.textAttributes['text-highlight'] = {
//     style: { backgroundColor: 'yellow' },
//     inheritable: true,
//   };

//   // eslint-disable-next-line no-undef
//   Trix.config.textAttributes['text-large'] = {
//     style: { fontSize: '1.5em' },
//     inheritable: true,
//   };

//   // eslint-disable-next-line no-undef
//   Trix.config.textAttributes['text-small'] = {
//     style: { fontSize: '0.75em' },
//     inheritable: true,
//   };
// });


// Register text attributes as soon as this module is evaluated so they exist
// before Trix editors initialize. This relies on import order: ensure
// `trix` and `@rails/actiontext` are imported before controllers in
// `app/javascript/application.js`.
function registerTextAttributes() {
  if (typeof Trix === 'undefined' || !Trix.config) {
    // If Trix isn't available yet, attach once to try to register at the
    // earliest possible moment. This is a fallback; prefer import ordering.
    document.addEventListener('trix-initialize', function _lateRegister() {
      registerTextAttributes();
    }, { once: true });
    return;
  }

  const exclusiveColors = ['text-red', 'text-blue', 'text-green', 'text-yellow'];

  exclusiveColors.forEach((color) => {
    const clr = color.split('-')[1];
    Trix.config.textAttributes[color] = {
      style: { color: clr },
      inheritable: true,
      parser(element) {
        return element.style && element.style.color === clr;
      },
      remover(element) {
        // Remove inline color style when removing the color attribute
        if (element.style) element.style.color = '';
      },
    };
  });

  Trix.config.textAttributes['text-underline'] = {
    style: { textDecoration: 'underline' },
    inheritable: true,
    parser(element) { return element.style && /underline/.test(element.style.textDecoration); },
    remover(element) { if (element.style) element.style.textDecoration = ''; },
  };

  Trix.config.textAttributes['text-highlight'] = {
    style: { backgroundColor: 'yellow' },
    inheritable: true,
    parser(element) { return element.style && element.style.backgroundColor === 'yellow'; },
    remover(element) { if (element.style) element.style.backgroundColor = ''; },
  };

  Trix.config.textAttributes['text-large'] = {
    style: { fontSize: '1.5em' },
    inheritable: true,
    parser(element) { return element.style && element.style.fontSize === '1.5em'; },
    remover(element) { if (element.style) element.style.fontSize = ''; },
  };

  Trix.config.textAttributes['text-small'] = {
    style: { fontSize: '0.75em' },
    inheritable: true,
    parser(element) { return element.style && element.style.fontSize === '0.75em'; },
    remover(element) { if (element.style) element.style.fontSize = ''; },
  };
}

// Execute immediately.
registerTextAttributes();

// Patch Trix sanitizer to allow table tags for pasted content
document.addEventListener('trix-before-initialize', () => {
  if (typeof Trix !== 'undefined' && Trix.config && Trix.config.sanitizer) {
    const allowedTags = [
      'TABLE', 'TBODY', 'THEAD', 'TFOOT', 'TR', 'TD', 'TH'
    ];
    const originalSanitize = Trix.config.sanitizer.sanitizeNode;
    Trix.config.sanitizer.sanitizeNode = function(node) {
      if (allowedTags.includes(node.nodeName)) {
        return node;
      }
      return originalSanitize.call(this, node);
    };
  }
});

// Insert custom buttons into a dedicated toolbar group so we don't mutate or
// overwrite built-in groups. Keep this insertion on trix-initialize because
// toolbarElement is only available per-editor at that time.
document.addEventListener('trix-initialize', (event) => {
  // Removed custom toolbar button insertion for safety; use only built-in buttons
});