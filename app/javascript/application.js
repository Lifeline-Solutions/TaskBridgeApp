// Configure your import map in config/import.rb. Read more: https://github.com/rails/importmap-rails

import '@hotwired/turbo-rails';
import 'controllers';
// Action Text (Trix) should be loaded before controllers so any code that
// registers Trix attributes runs before editors initialize.
import 'trix';
import '@rails/actiontext';

import './controllers/ckeditor_init'
import './controllers/label_tomselect_init' 

//= require rails-ujs
//= require turbolinks
//= require_tree .
//= require 'chartkick'
//= require 'chart.js'
// import "./channels"
//= require 'trix_custom_formatting_controller.js'


import "trix"
import "@rails/actiontext"
