`default_nettype none

// One Pattern-4 partition: N one_symbol_book instances.
// One in-flight command per book except Pattern 2: bid rest ∥ ask rest on the same book.
// Other books in the pipe still stall (no per-symbol scoreboard).
// local = cmd_symbol / N_PIPES_P. Spec: design/pattern-4.md
module symbol_bank
  import exch_pkg::*;
#(
  parameter int PIPE_ID   = 0,
  parameter int N_PIPES_P = 1,
  parameter int N_SYMS    = N_SYMS_PER_PIPE
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                cmd_valid,
  output wire                cmd_ready,
  input  wire [SYMBOL_W-1:0] cmd_symbol,
  input  wire                cmd_op,
  input  wire                cmd_side,
  input  wire [PRICE_W-1:0]  cmd_price,
  input  wire [QTY_W-1:0]    cmd_qty,
  input  wire [OID_W-1:0]    cmd_oid,

  output logic               rsp_valid,
  output logic               rsp_ok,
  output logic [OID_W-1:0]   rsp_oid,
  output logic [QTY_W-1:0]   rsp_filled_qty,
  output logic [QTY_W-1:0]   rsp_rest_qty,
  output logic [QTY_W-1:0]   rsp_unrested_qty,

  output logic               evt_valid,
  input  wire                evt_ready,
  output logic [OID_W-1:0]   evt_maker_oid,
  output logic [OID_W-1:0]   evt_taker_oid,
  output logic [PRICE_W-1:0] evt_price,
  output logic [QTY_W-1:0]   evt_qty,

  output logic               bbo_bid_valid,
  output logic [PRICE_W-1:0] bbo_bid_px,
  output logic [QTY_W-1:0]   bbo_bid_qty,
  output logic               bbo_ask_valid,
  output logic [PRICE_W-1:0] bbo_ask_px,
  output logic [QTY_W-1:0]   bbo_ask_qty
);

  localparam int LOC_W = $clog2(N_SYMS);

  wire [31:0]      loc_full_w = 32'(cmd_symbol) / 32'(N_PIPES_P);
  wire             pipe_ok    = (N_PIPES_P == 1) ||
                                (32'(cmd_symbol) % 32'(N_PIPES_P) == 32'(PIPE_ID));
  wire             in_range   = pipe_ok && (loc_full_w < 32'(N_SYMS));
  wire [LOC_W-1:0] loc        = loc_full_w[LOC_W-1:0];

  logic [N_SYMS-1:0] book_ready;
  logic [N_SYMS-1:0] book_idle;
  logic [N_SYMS-1:0] book_cmd_valid;
  logic [N_SYMS-1:0] book_rsp_valid, book_rsp_ok;
  logic [OID_W-1:0]  book_rsp_oid [N_SYMS];
  logic [QTY_W-1:0]  book_rsp_filled [N_SYMS];
  logic [QTY_W-1:0]  book_rsp_rest [N_SYMS];
  logic [QTY_W-1:0]  book_rsp_unrested [N_SYMS];
  logic [N_SYMS-1:0] book_evt_valid;
  logic [OID_W-1:0]  book_evt_maker [N_SYMS];
  logic [OID_W-1:0]  book_evt_taker [N_SYMS];
  logic [PRICE_W-1:0] book_evt_px [N_SYMS];
  logic [QTY_W-1:0]  book_evt_qty [N_SYMS];
  logic [N_SYMS-1:0] book_bid_v, book_ask_v;
  logic [PRICE_W-1:0] book_bid_px [N_SYMS];
  logic [QTY_W-1:0]  book_bid_qty [N_SYMS];
  logic [PRICE_W-1:0] book_ask_px [N_SYMS];
  logic [QTY_W-1:0]  book_ask_qty [N_SYMS];

  logic other_busy;
  always_comb begin
    other_busy = 1'b0;
    for (int i = 0; i < N_SYMS; i++) begin
      if (in_range && (LOC_W'(i) != loc) && !book_idle[i]) begin
        other_busy = 1'b1;
      end
    end
  end

  logic nak_busy;
  logic [OID_W-1:0] nak_oid;

  assign cmd_ready = rst_n && !nak_busy && (in_range ? (book_ready[loc] && !other_busy) : 1'b1);

  genvar gi;
  generate
    for (gi = 0; gi < N_SYMS; gi++) begin : gen_books
      assign book_cmd_valid[gi] = cmd_valid && cmd_ready && in_range && (loc == LOC_W'(gi));
      one_symbol_book u_book (
        .clk, .rst_n,
        .cmd_valid (book_cmd_valid[gi]),
        .cmd_ready (book_ready[gi]),
        .cmd_op, .cmd_side, .cmd_price, .cmd_qty, .cmd_oid,
        .idle      (book_idle[gi]),
        .rsp_valid (book_rsp_valid[gi]),
        .rsp_ok    (book_rsp_ok[gi]),
        .rsp_oid   (book_rsp_oid[gi]),
        .rsp_filled_qty (book_rsp_filled[gi]),
        .rsp_rest_qty   (book_rsp_rest[gi]),
        .rsp_unrested_qty (book_rsp_unrested[gi]),
        .evt_valid (book_evt_valid[gi]),
        .evt_ready,
        .evt_maker_oid (book_evt_maker[gi]),
        .evt_taker_oid (book_evt_taker[gi]),
        .evt_price (book_evt_px[gi]),
        .evt_qty   (book_evt_qty[gi]),
        .bbo_bid_valid (book_bid_v[gi]),
        .bbo_bid_px    (book_bid_px[gi]),
        .bbo_bid_qty   (book_bid_qty[gi]),
        .bbo_ask_valid (book_ask_v[gi]),
        .bbo_ask_px    (book_ask_px[gi]),
        .bbo_ask_qty   (book_ask_qty[gi])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      nak_busy <= 1'b0;
      nak_oid  <= '0;
    end else if (cmd_valid && cmd_ready && !in_range) begin
      nak_busy <= 1'b1;
      nak_oid  <= cmd_oid;
    end else begin
      nak_busy <= 1'b0;
    end
  end

  always_comb begin
    rsp_valid        = 1'b0;
    rsp_ok           = 1'b0;
    rsp_oid          = '0;
    rsp_filled_qty   = '0;
    rsp_rest_qty     = '0;
    rsp_unrested_qty = '0;
    evt_valid        = 1'b0;
    evt_maker_oid    = '0;
    evt_taker_oid    = '0;
    evt_price        = '0;
    evt_qty          = '0;
    bbo_bid_valid    = 1'b0;
    bbo_bid_px       = '0;
    bbo_bid_qty      = '0;
    bbo_ask_valid    = 1'b0;
    bbo_ask_px       = '0;
    bbo_ask_qty      = '0;
    for (int i = 0; i < N_SYMS; i++) begin
      if (book_rsp_valid[i]) begin
        rsp_valid        = 1'b1;
        rsp_ok           = book_rsp_ok[i];
        rsp_oid          = book_rsp_oid[i];
        rsp_filled_qty   = book_rsp_filled[i];
        rsp_rest_qty     = book_rsp_rest[i];
        rsp_unrested_qty = book_rsp_unrested[i];
      end
      if (book_evt_valid[i]) begin
        evt_valid     = 1'b1;
        evt_maker_oid = book_evt_maker[i];
        evt_taker_oid = book_evt_taker[i];
        evt_price     = book_evt_px[i];
        evt_qty       = book_evt_qty[i];
      end
    end
    if (in_range) begin
      bbo_bid_valid = book_bid_v[loc];
      bbo_bid_px    = book_bid_px[loc];
      bbo_bid_qty   = book_bid_qty[loc];
      bbo_ask_valid = book_ask_v[loc];
      bbo_ask_px    = book_ask_px[loc];
      bbo_ask_qty   = book_ask_qty[loc];
    end
    if (nak_busy) begin
      rsp_valid        = 1'b1;
      rsp_ok           = 1'b0;
      rsp_oid          = nak_oid;
      rsp_filled_qty   = '0;
      rsp_rest_qty     = '0;
      rsp_unrested_qty = '0;
    end
  end

endmodule

`default_nettype wire
