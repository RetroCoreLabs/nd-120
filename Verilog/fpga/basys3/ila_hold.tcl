source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set hw [get_hw_devices xc7a35t_0]
current_hw_device $hw
set_property PROBES.FILE      $b3_ltx $hw
set_property FULL_PROBES.FILE $b3_ltx $hw
refresh_hw_device $hw
set ila [get_hw_ilas -of_objects $hw]
set p2 [get_hw_probes -of_objects $ila s_debug_csa_2]
set p1 [get_hw_probes -of_objects $ila s_debug_csa_1]
set p9 [get_hw_probes -of_objects $ila s_debug_csa]
# o2001 (exec start after load): csa_2=0x1, csa=0x000, csa_1=0x1
set_property TRIGGER_COMPARE_VALUE eq3'h1   $p2
set_property TRIGGER_COMPARE_VALUE eq9'h000 $p9
set_property TRIGGER_COMPARE_VALUE eq1'h1   $p1
set_property CONTROL.TRIGGER_POSITION 20 $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
run_hw_ila $ila
puts "REALLY_ARMED_NOW"
flush stdout
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file [file join $b3_logdir ila_hold.csv] [current_hw_ila_data]
puts "HOLD_CAPTURED"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
