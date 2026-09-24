`default_nettype none

// Cold keys in a two-level tree. Node 0 is the root. Later keys hang off it.
// `visits` is how many nodes a lookup touches. A miss of the root costs 2
// once a second node exists.
module oid_tree
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
  output logic [3:0]         rd_slot,
  output logic [2:0]         visits
);

  logic [OID_W-1:0]   oid_m   [0:DEPTH-1];
  logic [7:0]         slice_m [0:DEPTH-1];
  logic [PRICE_W-1:0] price_m [0:DEPTH-1];
  logic [3:0]         slot_m  [0:DEPTH-1];
  logic               valid_m [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr;

  integer n;
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
    visits   = 3'd0;
    if (valid_m[0]) begin
      visits = 3'd1;
      if (oid_m[0] == rd_oid) begin
        hit      = 1'b1;
        rd_slice = slice_m[0];
        rd_price = price_m[0];
        rd_slot  = slot_m[0];
      end else if (valid_m[1]) begin
        visits = 3'd2;
        for (n = 1; n < DEPTH; n = n + 1) begin
          if (!hit && valid_m[n] && oid_m[n] == rd_oid) begin
            hit      = 1'b1;
            rd_slice = slice_m[n];
            rd_price = price_m[n];
            rd_slot  = slot_m[n];
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
