# Capture the ILA on the running FPGA and dump to CSV. Forces an immediate
# trigger (captures whatever the CPU is doing right now).
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set hw [get_hw_devices xc7a35t_0]
current_hw_device $hw
refresh_hw_device -update_hw_probes false $hw
set_property PROBES.FILE      $b3_ltx $hw
set_property FULL_PROBES.FILE $b3_ltx $hw
refresh_hw_device $hw

set ila [get_hw_ilas -of_objects $hw]
puts "ILA: $ila"
puts "PROBES:"
foreach pr [get_hw_probes -of_objects $ila] { puts "  $pr" }

# Immediate capture: trigger now, sample window at position 0.
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
run_hw_ila -trigger_now $ila
wait_on_hw_ila $ila
upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file [file join $b3_logdir ila_cap.csv] [current_hw_ila_data]
puts "WROTE_CSV"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
