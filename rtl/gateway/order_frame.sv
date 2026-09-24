`default_nettype none

// One order word in, one slice command port out. A busy slice holds only
// its own word. The other slices' command ports stay clear.
module order_frame
  import exch_pkg::*;
#(
  parameter int N = 4
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                word_valid,
  output wire                word_ready,
  input  wire                word_op,
  input  wire                word_side,
  input  wire [SYMBOL_W-1:0] word_symbol,
  input  wire [PRICE_W-1:0]  word_price,
  input  wire [QTY_W-1:0]    word_qty,
  input  wire [OID_W-1:0]    word_oid,

  output logic [N-1:0]       cmd_valid,
  input  wire  [N-1:0]       cmd_ready,
  output logic [N-1:0]       cmd_op,
  output logic [N-1:0]       cmd_side,
  output logic [PRICE_W-1:0] cmd_price [N],
  output logic [QTY_W-1:0]   cmd_qty [N],
  output logic [OID_W-1:0]   cmd_oid [N],

  output logic               reject_valid,
  output logic [7:0]         reject_reason,
  output logic [OID_W-1:0]   reject_oid,
  output logic               fired
);

  wire in_range = (word_symbol < SYMBOL_W'(N));
  wire [$clog2(N)-1:0] dest = word_symbol[$clog2(N)-1:0];
  wire dest_ready = cmd_ready[dest];

  assign word_ready = rst_n && (!word_valid || (in_range ? dest_ready : 1'b1));

  always_comb begin
    cmd_valid     = '0;
    cmd_op        = '0;
    cmd_side      = '0;
    reject_valid  = 1'b0;
    reject_reason = 8'd0;
    reject_oid    = word_oid;
    for (int i = 0; i < N; i++) begin
      cmd_price[i] = '0;
      cmd_qty[i]   = '0;
      cmd_oid[i]   = '0;
    end
    if (word_valid && word_ready) begin
      if (!in_range) begin
        reject_valid  = 1'b1;
        reject_reason = 8'd1;
      end else begin
        cmd_valid[dest] = 1'b1;
        cmd_op[dest]    = word_op;
        cmd_side[dest]  = word_side;
        cmd_price[dest] = word_price;
        cmd_qty[dest]   = word_qty;
        cmd_oid[dest]   = word_oid;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) fired <= 1'b0;
    else        fired <= word_valid && word_ready && in_range;
  end

endmodule

`default_nettype wire
