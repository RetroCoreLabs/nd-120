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

# Trigger when UART TX goes LOW (a start bit = the CPU is transmitting).
set txp [get_hw_probes -of_objects $ila *uartTx*]
puts "TXPROBE $txp"
set_property TRIGGER_COMPARE_VALUE eq1'b0 $txp
set_property CONTROL.TRIGGER_POSITION 64 $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
run_hw_ila $ila
# Wait up to ~8s for a TX start bit
set ok [wait_on_hw_ila -timeout 8 $ila]
set st [get_property CORE_STATUS $ila]
puts "TX_TRIG_STATUS $st"
if {$st eq "Idle"} {
  upload_hw_ila_data $ila
  write_hw_ila_data -force -csv_file [file join $b3_logdir ila_uart.csv] [current_hw_ila_data]
  puts "TX_CAPTURED"
} else {
  puts "NO_TX_DETECTED (CPU is not transmitting - it is silent, waiting for RX)"
  # abort the armed core
  reset_hw_ila $ila
}
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
