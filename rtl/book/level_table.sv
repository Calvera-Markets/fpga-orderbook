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

  logic                hit_m [0:PRICE_WIN-1];
  logic [LVL_IDX_W-1:0] slot_m [0:PRICE_WIN-1];

  assign in_window = (probe < PRICE_WIN);

  always_comb begin
    for (int p = 0; p < PRICE_WIN; p++) begin
      hit_m[p]  = 1'b0;
      slot_m[p] = '0;
    end
    for (int i = 0; i < N_LEVELS; i++) begin
      if (used[i] && px[i] < PRICE_WIN) begin
        hit_m[px[i]]  = 1'b1;
        slot_m[px[i]] = LVL_IDX_W'(i);
      end
    end
    hit  = in_window && hit_m[probe];
    slot = in_window ? slot_m[probe] : '0;
  end

endmodule

`default_nettype wire
