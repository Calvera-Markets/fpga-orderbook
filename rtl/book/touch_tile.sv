`default_nettype none

// One resident price on a side. An empty line is a hit: the first
// order installs it. A different price is a miss for the caller.
module touch_tile
  import exch_pkg::*;
(
  input  wire                clk,
  input  wire                rst_n,
  input  wire                set_valid,
  input  wire [PRICE_W-1:0]  set_price,
  input  wire [PRICE_W-1:0]  probe,
  output logic               valid,
  output logic               hit
);

  logic [PRICE_W-1:0] tag;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid <= 1'b0;
      tag   <= '0;
    end else if (set_valid) begin
      valid <= 1'b1;
      tag   <= set_price;
    end
  end

  assign hit = !valid || (probe == tag);

endmodule

`default_nettype wire
