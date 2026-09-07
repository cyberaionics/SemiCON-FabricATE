module ltssm #(
  parameter integer DETECT_WAIT_CYCLES = 2,
  parameter integer TRAIN_WAIT_CYCLES  = 2,
  parameter integer CONFIG_WAIT_CYCLES = 2,
  parameter integer RECOVERY_WAIT_CYCLES = 2
)(
  input  logic clk,
  input  logic rst_n,

  input  logic phy_rx_detected,
  input  logic training_done,
  input  logic link_width_ok,
  input  logic lane_config_ok,

  input  logic recovery_request,
  input  logic phy_error,
  input  logic disable_request,
  input  logic hot_reset_request,

  output logic link_up,
  output logic tx_enable,
  output logic rx_enable,
  output logic training_enable,
  output logic recovery_active,
  output logic [5:0] state,
  output logic state_changed
);

  localparam [5:0]
    DETECT_QUIET = 6'h00,
    DETECT_ACTIVE = 6'h01,
    POLLING_ACTIVE = 6'h02,
    POLLING_CONFIGURATION = 6'h04,
    CONFIG_LINKWIDTH_START = 6'h05,
    CONFIG_LINKWIDTH_ACCEPT = 6'h06,
    CONFIG_LANENUM_WAIT = 6'h08,
    CONFIG_LANENUM_ACCEPT = 6'h07,
    CONFIG_COMPLETE = 6'h09,
    CONFIG_IDLE = 6'h0A,
    L0 = 6'h10,
    RECOVERY = 6'h0B,
    DISABLED = 6'h20,
    HOT_RESET = 6'h27;

  logic [5:0] state_q, state_d;
  integer timer_q, timer_d;

  function automatic integer wait_cycles(input integer n);
    if (n < 1) wait_cycles = 1;
    else wait_cycles = n;
  endfunction

  always_comb begin
    state_d = state_q;
    timer_d = timer_q;

    case (state_q)
      DETECT_QUIET: begin
        timer_d = 0;
        if (disable_request) state_d = DISABLED;
        else state_d = DETECT_ACTIVE;
      end

      DETECT_ACTIVE: begin
        if (disable_request) begin state_d = DISABLED; timer_d = 0; end
        else if (hot_reset_request) begin state_d = HOT_RESET; timer_d = 0; end
        else if (phy_rx_detected) begin state_d = POLLING_ACTIVE; timer_d = 0; end
      end

      POLLING_ACTIVE: begin
        if (disable_request) begin state_d = DISABLED; timer_d = 0; end
        else if (hot_reset_request) begin state_d = HOT_RESET; timer_d = 0; end
        else if (timer_q >= wait_cycles(TRAIN_WAIT_CYCLES)-1) begin
          state_d = POLLING_CONFIGURATION; timer_d = 0;
        end else timer_d = timer_q + 1;
      end

      POLLING_CONFIGURATION: begin
        if (disable_request) begin state_d = DISABLED; timer_d = 0; end
        else if (training_done) begin state_d = CONFIG_LINKWIDTH_START; timer_d = 0; end
        else timer_d = timer_q + 1;
      end

      CONFIG_LINKWIDTH_START: begin
        if (link_width_ok) state_d = CONFIG_LINKWIDTH_ACCEPT;
      end

      CONFIG_LINKWIDTH_ACCEPT: begin
        if (lane_config_ok) state_d = CONFIG_LANENUM_WAIT;
      end

      CONFIG_LANENUM_WAIT: begin
        state_d = CONFIG_LANENUM_ACCEPT;
      end

      CONFIG_LANENUM_ACCEPT: begin
        state_d = CONFIG_COMPLETE;
      end

      CONFIG_COMPLETE: begin
        state_d = CONFIG_IDLE;
      end

      CONFIG_IDLE: begin
        if (timer_q >= wait_cycles(CONFIG_WAIT_CYCLES)-1) begin
          state_d = L0; timer_d = 0;
        end else timer_d = timer_q + 1;
      end

      L0: begin
        timer_d = 0;
        if (disable_request) state_d = DISABLED;
        else if (hot_reset_request) state_d = HOT_RESET;
        else if (recovery_request || phy_error) state_d = RECOVERY;
      end

      RECOVERY: begin
        if (disable_request) begin state_d = DISABLED; timer_d = 0; end
        else if (hot_reset_request) begin state_d = HOT_RESET; timer_d = 0; end
        else if (timer_q >= wait_cycles(RECOVERY_WAIT_CYCLES)-1) begin
          state_d = L0; timer_d = 0;
        end else timer_d = timer_q + 1;
      end

      DISABLED: begin
        timer_d = 0;
        if (hot_reset_request) state_d = HOT_RESET;
        else if (!disable_request) state_d = DETECT_QUIET;
      end

      HOT_RESET: begin
        timer_d = 0;
        if (!hot_reset_request) state_d = DETECT_QUIET;
      end

      default: begin
        state_d = DETECT_QUIET;
        timer_d = 0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= DETECT_QUIET;
      timer_q <= 0;
    end else begin
      state_q <= state_d;
      timer_q <= timer_d;
    end
  end

  always_comb begin
    state = state_q;
    state_changed = (state_d != state_q);
    link_up = (state_q == L0);
    tx_enable = (state_q == L0);
    rx_enable = (state_q == L0) || (state_q == RECOVERY);
    training_enable = (state_q == DETECT_ACTIVE) ||
                      (state_q == POLLING_ACTIVE) ||
                      (state_q == POLLING_CONFIGURATION) ||
                      (state_q == CONFIG_LINKWIDTH_START) ||
                      (state_q == CONFIG_LINKWIDTH_ACCEPT) ||
                      (state_q == CONFIG_LANENUM_WAIT) ||
                      (state_q == CONFIG_LANENUM_ACCEPT) ||
                      (state_q == CONFIG_COMPLETE) ||
                      (state_q == CONFIG_IDLE);
    recovery_active = (state_q == RECOVERY);
  end
endmodule
