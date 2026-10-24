export DESIGN_NAME = integrated_link_phy_top
export PLATFORM = nangate45

export VERILOG_FILES = \
  /work/rtl/axis_fifo.sv \
  /work/rtl/packet_rr_arbiter.sv \
  /work/rtl/axis_interconnect_2to1.sv \
  /work/rtl/flit_crc8.sv \
  /work/rtl/flit_fec6.sv \
  /work/rtl/axis_frame_packetizer.sv \
  /work/rtl/axis_link_tx.sv \
  /work/rtl/lane_striper.sv \
  /work/rtl/lane_scrambler.sv \
  /work/rtl/gray_pam4_tx.sv \
  /work/rtl/gray_pam4_rx.sv \
  /work/rtl/lane_destriper.sv \
  /work/rtl/protocol_to_phy_tx.sv \
  /work/rtl/protocol_to_phy_rx.sv \
  /work/rtl/ltssm.sv \
  /work/rtl/protocol_to_phy_top.sv \
  /work/rtl/integrated_link_phy_top.sv

export SDC_FILE = /work/synthesis/orfs/constraint.sdc
export ABC_AREA = 1
export SYNTH_REPEATABLE_BUILD = 1
export CORE_UTILIZATION = 40
