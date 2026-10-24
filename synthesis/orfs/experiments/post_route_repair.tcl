puts "=== BEFORE REPAIR ==="
report_checks -path_delay max
report_check_types -max_cap -max_slew -max_fanout -violators

puts "=== RUNNING DESIGN REPAIR ==="
repair_design -verbose

puts "=== AFTER REPAIR ==="
report_checks -path_delay max
report_check_types -max_cap -max_slew -max_fanout -violators

puts "=== REPAIR EXPERIMENT COMPLETE ==="
