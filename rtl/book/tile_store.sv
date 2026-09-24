`default_nettype none

// Timed tile port. FETCH then WRITEBACK. The stored word is the evicted price.
module tile_store
  import exch_pkg::*;
#(
  parameter int FETCH_CYCLES = 2,
  parameter int WRITEBACK_CYCLES = 2
) (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                wr_en,
  input  wire [PRICE_W-1:0]  wr_px,
  output logic [2:0]         latency,
  output logic               last_valid,
  output logic [PRICE_W-1:0] last_px
);

  assign latency = 3'(FETCH_CYCLES + WRITEBACK_CYCLES);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      last_valid <= 1'b0;
      last_px    <= '0;
    end else if (wr_en) begin
      last_valid <= 1'b1;
      last_px    <= wr_px;
    end
  end

endmodule

`default_nettype wire
