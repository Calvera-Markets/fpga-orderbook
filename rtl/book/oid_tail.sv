`default_nettype none

// Cold order ids. A linear list, not the hot hash.
// The caller waits before it trusts a miss; this read itself is combinational.
module oid_tail
  import exch_pkg::*;
#(
  parameter int DEPTH = 16
) (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                wr_en,
  input  wire [OID_W-1:0]    wr_oid,
  input  wire [7:0]          wr_slice,
  input  wire [PRICE_W-1:0]  wr_price,
  input  wire [3:0]          wr_slot,
  input  wire [OID_W-1:0]    rd_oid,
  output logic               hit,
  output logic [7:0]         rd_slice,
  output logic [PRICE_W-1:0] rd_price,
  output logic [3:0]         rd_slot
);

  logic [OID_W-1:0]   oid_m   [0:DEPTH-1];
  logic [7:0]         slice_m [0:DEPTH-1];
  logic [PRICE_W-1:0] price_m [0:DEPTH-1];
  logic [3:0]         slot_m  [0:DEPTH-1];
  logic               valid_m [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      for (int i = 0; i < DEPTH; i++) valid_m[i] <= 1'b0;
    end else if (wr_en) begin
      valid_m[wr_ptr] <= 1'b1;
      oid_m[wr_ptr]   <= wr_oid;
      slice_m[wr_ptr] <= wr_slice;
      price_m[wr_ptr] <= wr_price;
      slot_m[wr_ptr]  <= wr_slot;
      wr_ptr          <= wr_ptr + 1'b1;
    end
  end

  always_comb begin
    hit      = 1'b0;
    rd_slice = '0;
    rd_price = '0;
    rd_slot  = '0;
    for (int i = 0; i < DEPTH; i++) begin
      if (!hit && valid_m[i] && oid_m[i] == rd_oid) begin
        hit      = 1'b1;
        rd_slice = slice_m[i];
        rd_price = price_m[i];
        rd_slot  = slot_m[i];
      end
    end
  end

endmodule

`default_nettype wire
