`default_nettype none

// A price is an address: offset = probe - base.
// Occupied ticks are a mask. The queue id behind a tick is the slot.
module tick_array
  import exch_pkg::*;
#(
  parameter int WINDOW = 32
) (
  input  wire [PRICE_W-1:0]    base,
  input  wire [N_LEVELS-1:0]   used,
  input  wire [PRICE_W-1:0]    px [N_LEVELS],
  input  wire [PRICE_W-1:0]    probe,
  output wire                  in_window,
  output logic                 hit,
  output logic [LVL_IDX_W-1:0] slot
);

  localparam int OFF_W = (WINDOW <= 1) ? 1 : $clog2(WINDOW);

  logic [WINDOW-1:0]    mask;
  logic [LVL_IDX_W-1:0] slot_m [0:WINDOW-1];
  wire                  above = (probe >= base);
  wire [PRICE_W-1:0]    delta = probe - base;
  wire [OFF_W-1:0]      idx   = delta[OFF_W-1:0];

  assign in_window = above && (delta < WINDOW);

  always_comb begin
    mask = '0;
    for (int t = 0; t < WINDOW; t++) slot_m[t] = '0;
    for (int i = 0; i < N_LEVELS; i++) begin
      if (used[i] && px[i] >= base && (px[i] - base) < WINDOW) begin
        mask[px[i] - base]   = 1'b1;
        slot_m[px[i] - base] = LVL_IDX_W'(i);
      end
    end
    hit  = in_window && mask[idx];
    slot = in_window ? slot_m[idx] : '0;
  end

endmodule

`default_nettype wire
