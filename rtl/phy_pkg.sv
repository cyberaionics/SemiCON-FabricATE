package phy_pkg;
  localparam int DATA_W = 256;
  localparam int LANES  = 4;
  localparam int LANE_W = DATA_W / LANES;
  localparam int SYMBOL_W = 2;

  typedef enum logic [5:0] {
    ST_DETECT_QUIET             = 6'h00,
    ST_DETECT_ACTIVE            = 6'h01,
    ST_POLLING_ACTIVE           = 6'h02,
    ST_POLLING_CONFIGURATION    = 6'h04,
    ST_CONFIG_LINKWIDTH_START   = 6'h05,
    ST_CONFIG_LINKWIDTH_ACCEPT  = 6'h06,
    ST_CONFIG_LANENUM_WAIT      = 6'h08,
    ST_CONFIG_LANENUM_ACCEPT    = 6'h07,
    ST_CONFIG_COMPLETE           = 6'h09,
    ST_CONFIG_IDLE               = 6'h0A,
    ST_L0                        = 6'h10,
    ST_RECOVERY                  = 6'h0B,
    ST_DISABLED                  = 6'h20,
    ST_HOT_RESET                 = 6'h27
  } ltssm_state_t;
endpackage
