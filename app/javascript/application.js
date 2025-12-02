// Configure your import map in config/import.rb. Read more: https://github.com/rails/importmap-rails

import '@hotwired/turbo-rails';
import 'controllers';
// Action Text (Trix) should be loaded before controllers so any code that
// registers Trix attributes runs before editors initialize.
import 'trix';
import '@rails/actiontext';

// Configuration files (not Stimulus controllers)
import 'config/groupware';
import 'config/trix_custom_formatting';

/* import './controllers/ckeditor_init' */

// Channels
// import "channels"
