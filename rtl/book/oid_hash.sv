`default_nettype none

// Hot order ids. Index is the low nibble. A hit returns the place.
// This module does not match.
module oid_hash
  import exch_pkg::*;
#(
  parameter int DEPTH = 16
) (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                wr_en,
  input  wire                wr_clear,
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

  localparam int IDX = $clog2(DEPTH);

  logic [OID_W-1:0]   oid_m   [0:DEPTH-1];
  logic [7:0]         slice_m [0:DEPTH-1];
  logic [PRICE_W-1:0] price_m [0:DEPTH-1];
  logic [3:0]         slot_m  [0:DEPTH-1];
  logic               valid_m [0:DEPTH-1];

  wire [IDX-1:0] wi = wr_oid[IDX-1:0];
  wire [IDX-1:0] ri = rd_oid[IDX-1:0];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH; i++) valid_m[i] <= 1'b0;
    end else if (wr_clear && valid_m[wi] && oid_m[wi] == wr_oid) begin
      valid_m[wi] <= 1'b0;
    end else if (wr_en) begin
      valid_m[wi] <= 1'b1;
      oid_m[wi]   <= wr_oid;
      slice_m[wi] <= wr_slice;
      price_m[wi] <= wr_price;
      slot_m[wi]  <= wr_slot;
    end
  end

  assign hit      = valid_m[ri] && (oid_m[ri] == rd_oid);
  assign rd_slice = slice_m[ri];
  assign rd_price = price_m[ri];
  assign rd_slot  = slot_m[ri];

endmodule

`default_nettype wire
