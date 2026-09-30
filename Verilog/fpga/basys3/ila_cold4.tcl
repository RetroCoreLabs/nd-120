source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set hw [get_hw_devices xc7a35t_0]
current_hw_device $hw
set_property PROGRAM.FILE $b3_bit $hw
set_property PROBES.FILE      $b3_ltx $hw
set_property FULL_PROBES.FILE $b3_ltx $hw
program_hw_devices $hw
refresh_hw_device $hw
set ila [get_hw_ilas -of_objects $hw]
set_property CONTROL.DATA_DEPTH 1024 $ila
# Immediate capture to verify held-state (write CSV; read lcs_n from it later)
run_hw_ila -trigger_now $ila
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file [file join $b3_logdir ila_cold4_check.csv] [current_hw_ila_data]
# Arm real trigger: lcs_n rises when load completes after SW0 release
set lcs [get_hw_probes -of_objects $ila s_debug_lcs_n]
set_property TRIGGER_COMPARE_VALUE eq1'h1 $lcs
set_property CONTROL.TRIGGER_POSITION 20 $ila
run_hw_ila $ila
puts "REALLY_ARMED_NOW"
flush stdout
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file [file join $b3_logdir ila_cold4.csv] [current_hw_ila_data]
puts "COLD4_CAPTURED"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
