`default_nettype none

// Isolation grain of the sharded matcher. One slice owns one symbol and
// one book. Each slice has its own command port and its own evt_ready.
// A walk or a held fill on slice A does not change cmd_ready or evt_ready
// on slice B. Spec: design/sharded-matcher.md
//
// The book inside the slice is still the resident 8x16 price-time book.
// A tile cache and an order-id map are not this module. An algo other
// than FIFO is accepted and NAKed here so the host can run it. The book
// is not touched.
module slice_engine
  import exch_pkg::*;
#(
  parameter int N_SLICES = 4
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                cfg_valid,
  output wire                cfg_ready,
  input  wire [$clog2(N_SLICES)-1:0] cfg_slice,
  input  wire [SYMBOL_W-1:0] cfg_symbol,
  input  wire [1:0]          cfg_algo,

  input  wire [N_SLICES-1:0] cmd_valid,
  output logic [N_SLICES-1:0] cmd_ready,
  input  wire [N_SLICES-1:0] cmd_op,
  input  wire [N_SLICES-1:0] cmd_side,
  input  wire [PRICE_W-1:0]  cmd_price [N_SLICES],
  input  wire [QTY_W-1:0]    cmd_qty [N_SLICES],
  input  wire [OID_W-1:0]    cmd_oid [N_SLICES],

  output logic [N_SLICES-1:0] rsp_valid,
  output logic [N_SLICES-1:0] rsp_ok,
  output logic [OID_W-1:0]    rsp_oid [N_SLICES],
  output logic [QTY_W-1:0]    rsp_filled_qty [N_SLICES],
  output logic [QTY_W-1:0]    rsp_rest_qty [N_SLICES],
  output logic [QTY_W-1:0]    rsp_unrested_qty [N_SLICES],

  output logic [N_SLICES-1:0] evt_valid,
  input  wire [N_SLICES-1:0]  evt_ready,
  output logic [OID_W-1:0]    evt_maker_oid [N_SLICES],
  output logic [OID_W-1:0]    evt_taker_oid [N_SLICES],
  output logic [PRICE_W-1:0]  evt_price [N_SLICES],
  output logic [QTY_W-1:0]    evt_qty [N_SLICES],

  output logic [SYMBOL_W-1:0] slice_symbol [N_SLICES],
  output logic [1:0]          slice_algo [N_SLICES],
  output logic [N_SLICES-1:0] slice_idle,

  output logic [N_SLICES-1:0] bbo_bid_valid,
  output logic [PRICE_W-1:0]  bbo_bid_px [N_SLICES],
  output logic [QTY_W-1:0]    bbo_bid_qty [N_SLICES],
  output logic [N_SLICES-1:0] bbo_ask_valid,
  output logic [PRICE_W-1:0]  bbo_ask_px [N_SLICES],
  output logic [QTY_W-1:0]    bbo_ask_qty [N_SLICES]
);

  logic [SYMBOL_W-1:0] sym_q [N_SLICES];
  logic [1:0]          algo_q [N_SLICES];
  logic [N_SLICES-1:0] nak_busy;
  logic [OID_W-1:0]    nak_oid [N_SLICES];
  logic [N_SLICES-1:0] fifo_algo;

  logic [N_SLICES-1:0] book_cmd_valid;
  logic [N_SLICES-1:0] book_cmd_ready;
  logic [N_SLICES-1:0] book_idle;
  logic [N_SLICES-1:0] book_rsp_valid, book_rsp_ok;
  logic [OID_W-1:0]    book_rsp_oid [N_SLICES];
  logic [QTY_W-1:0]    book_rsp_filled [N_SLICES];
  logic [QTY_W-1:0]    book_rsp_rest [N_SLICES];
  logic [QTY_W-1:0]    book_rsp_unrested [N_SLICES];
  logic [N_SLICES-1:0] book_evt_valid;
  logic [OID_W-1:0]    book_evt_maker [N_SLICES];
  logic [OID_W-1:0]    book_evt_taker [N_SLICES];
  logic [PRICE_W-1:0]  book_evt_px [N_SLICES];
  logic [QTY_W-1:0]    book_evt_qty [N_SLICES];
  logic [N_SLICES-1:0] book_bid_v, book_ask_v;
  logic [PRICE_W-1:0]  book_bid_px [N_SLICES];
  logic [QTY_W-1:0]    book_bid_qty [N_SLICES];
  logic [PRICE_W-1:0]  book_ask_px [N_SLICES];
  logic [QTY_W-1:0]    book_ask_qty [N_SLICES];

  always_comb begin
    for (int i = 0; i < N_SLICES; i++) begin
      fifo_algo[i]        = (algo_q[i] == ALGO_FIFO);
      slice_symbol[i]     = sym_q[i];
      slice_algo[i]       = algo_q[i];
      slice_idle[i]       = book_idle[i] && !nak_busy[i];
      cmd_ready[i]        = rst_n && (fifo_algo[i] ? book_cmd_ready[i] : !nak_busy[i]);
      book_cmd_valid[i]   = cmd_valid[i] && cmd_ready[i] && fifo_algo[i];
      rsp_valid[i]        = fifo_algo[i] ? book_rsp_valid[i] : nak_busy[i];
      rsp_ok[i]           = fifo_algo[i] ? book_rsp_ok[i] : 1'b0;
      rsp_oid[i]          = fifo_algo[i] ? book_rsp_oid[i] : nak_oid[i];
      rsp_filled_qty[i]   = fifo_algo[i] ? book_rsp_filled[i] : '0;
      rsp_rest_qty[i]     = fifo_algo[i] ? book_rsp_rest[i] : '0;
      rsp_unrested_qty[i] = fifo_algo[i] ? book_rsp_unrested[i] : '0;
      evt_valid[i]        = book_evt_valid[i];
      evt_maker_oid[i]    = book_evt_maker[i];
      evt_taker_oid[i]    = book_evt_taker[i];
      evt_price[i]        = book_evt_px[i];
      evt_qty[i]          = book_evt_qty[i];
      bbo_bid_valid[i]    = book_bid_v[i];
      bbo_bid_px[i]       = book_bid_px[i];
      bbo_bid_qty[i]      = book_bid_qty[i];
      bbo_ask_valid[i]    = book_ask_v[i];
      bbo_ask_px[i]       = book_ask_px[i];
      bbo_ask_qty[i]      = book_ask_qty[i];
    end
  end

  assign cfg_ready = rst_n && slice_idle[cfg_slice] && !cmd_valid[cfg_slice];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < N_SLICES; i++) begin
        sym_q[i]    <= SYMBOL_W'(i);
        algo_q[i]   <= ALGO_FIFO;
        nak_busy[i] <= 1'b0;
        nak_oid[i]  <= '0;
      end
    end else begin
      for (int i = 0; i < N_SLICES; i++) begin
        if (cmd_valid[i] && cmd_ready[i] && !fifo_algo[i]) begin
          nak_busy[i] <= 1'b1;
          nak_oid[i]  <= cmd_oid[i];
        end else begin
          nak_busy[i] <= 1'b0;
        end
      end
      if (cfg_valid && cfg_ready) begin
        sym_q[cfg_slice]  <= cfg_symbol;
        algo_q[cfg_slice] <= cfg_algo;
      end
    end
  end

  genvar gi;
  generate
    for (gi = 0; gi < N_SLICES; gi++) begin : gen_slice
      one_symbol_book u_book (
        .clk, .rst_n,
        .cmd_valid (book_cmd_valid[gi]),
        .cmd_ready (book_cmd_ready[gi]),
        .cmd_op    (cmd_op[gi]),
        .cmd_side  (cmd_side[gi]),
        .cmd_price (cmd_price[gi]),
        .cmd_qty   (cmd_qty[gi]),
        .cmd_oid   (cmd_oid[gi]),
        .rsp_valid (book_rsp_valid[gi]),
        .rsp_ok    (book_rsp_ok[gi]),
        .rsp_oid   (book_rsp_oid[gi]),
        .rsp_filled_qty   (book_rsp_filled[gi]),
        .rsp_rest_qty     (book_rsp_rest[gi]),
        .rsp_unrested_qty (book_rsp_unrested[gi]),
        .evt_valid (book_evt_valid[gi]),
        .evt_ready (evt_ready[gi]),
        .evt_maker_oid (book_evt_maker[gi]),
        .evt_taker_oid (book_evt_taker[gi]),
        .evt_price (book_evt_px[gi]),
        .evt_qty   (book_evt_qty[gi]),
        .idle      (book_idle[gi]),
        .bbo_bid_valid (book_bid_v[gi]),
        .bbo_bid_px    (book_bid_px[gi]),
        .bbo_bid_qty   (book_bid_qty[gi]),
        .bbo_ask_valid (book_ask_v[gi]),
        .bbo_ask_px    (book_ask_px[gi]),
        .bbo_ask_qty   (book_ask_qty[gi])
      );
    end
  endgenerate

endmodule

`default_nettype wire
