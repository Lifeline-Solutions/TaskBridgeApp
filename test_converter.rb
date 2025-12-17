require_relative 'scripts/enhanced_adf_converter'
require 'json'

json = <<JSON
{
  "type": "doc",
  "version": 1,
  "content": [
    {
      "type": "paragraph",
      "content": [
        {
          "type": "text",
          "text": "Partially fixed. Now the user can select the Branch from the Branch Id popup. However the branch popup needs to be changed."
        }
      ]
    },
    {
      "type": "orderedList",
      "attrs": {
        "order": 1
      },
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [
                {
                  "type": "text",
                  "text": "See the header displayed below the branch title bar. That needs to be removed. ",
                  "marks": [
                    {
                      "type": "textColor",
                      "attrs": {
                        "color": "#ff5630"
                      }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
JSON

data = JSON.parse(json)
puts "--- CONVERTING ---"
puts convert_adf_to_html_enhanced(data['content'])
