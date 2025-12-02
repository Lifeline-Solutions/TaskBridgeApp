#!/usr/bin/env ruby
# Quick test for parse_module_and_submodule helper

require_relative './import_jira_with_modules'

cases = [
  ["Core Banking - Accounts - Savings", ""],
  ["Loans–Disbursement–Mobile", ""], # en-dash
  ["Cards — Debit — Prepaid", ""],   # em-dash
  ["Treasury-Backoffice", ""],
  ["Payments - Switch Integration", "Retail"], # explicit submodule provided
  ["No Hyphen Module", ""],
  ["  With  Spaces  -  Sub  -  More ", ""],
]

puts "Testing parse_module_and_submodule(...)"
puts "=" * 60
cases.each_with_index do |(mod, sub), idx|
  m, s = parse_module_and_submodule(mod, sub)
  puts "##{idx+1}: input module=#{mod.inspect}, sub=#{sub.inspect}"
  puts "     => parsed module=#{m.inspect}, submodule=#{s.inspect}"
end

