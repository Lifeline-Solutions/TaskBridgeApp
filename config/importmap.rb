# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/config", under: "config"
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"
pin "application", preload: true
pin "tributejs", to: "https://ga.jspm.io/npm:tributejs@5.1.3/dist/tribute.min.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"
#Add CK editor
pin "ckeditor", to: "https://cdn.ckeditor.com/4.25.1-lts/standard-all/ckeditor.js"
pin "slim-select", to: "https://ga.jspm.io/npm:slim-select@2.10.0/dist/slimselect.es.js"
