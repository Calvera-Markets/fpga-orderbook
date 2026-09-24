`default_nettype none

// Price is the address. The occupied set is at most N_LEVELS queues.
// probe >= PRICE_WIN is outside the on-chip window.
module level_table
  import exch_pkg::*;
(
  input  wire [N_LEVELS-1:0]  used,
  input  wire [PRICE_W-1:0]   px [N_LEVELS],
  input  wire [PRICE_W-1:0]   probe,
  output wire                 in_window,
  output logic                hit,
  output logic [LVL_IDX_W-1:0] slot
);

  tick_array #(.WINDOW(PRICE_WIN)) u_ticks (
    .base(32'd0),
    .used(used),
    .px(px),
    .probe(probe),
    .in_window(in_window),
    .hit(hit),
    .slot(slot)
  );

endmodule

`default_nettype wire
