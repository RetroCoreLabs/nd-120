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
set rp [get_hw_probes -of_objects $ila {CPU_BOARD/sys_rst_n}]
puts "RSTPROBE [llength $rp]"
set_property TRIGGER_COMPARE_VALUE eq1'h0 $rp
set_property CONTROL.TRIGGER_POSITION 50 $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
run_hw_ila $ila
puts "ARMED_TOGGLE_SW0"
flush stdout
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file [file join $b3_logdir ila_sysrst.csv] [current_hw_ila_data]
puts "SYSRST_CAPTURED"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
