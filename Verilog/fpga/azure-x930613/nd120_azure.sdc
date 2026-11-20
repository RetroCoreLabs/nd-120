# Timing for the Azure card build (nd120_azure.qsf).
#
# Only the CPU clock is stated. On the card it will come from a PLL off the
# 125 MHz oscillator (not written yet, docs/00-plan.md step V5); until then
# it is the top's clk_cpu port. The PCIe user clock comes from the PCIe hard
# block, which Quartus times from that block's own constraints once it
# exists. The two domains meet only at nd_storage_hps (its own crossing)
# and the console serial lines (console_uart_rx resynchronises).
create_clock -name clk_cpu -period 50.000 [get_ports {clk_cpu}]
derive_clock_uncertainty
