`default_nettype none

// One-symbol price-time book. Spec: design/one-symbol-book.md
// Pattern 2: bid rest ∥ ask rest; crossing LIMIT and CANCEL take both sides.
// IMP-001: taker walk is lookup → match → writeback with valid/ready.
module one_symbol_book
  import exch_pkg::*;
(
  input  wire                clk,
  input  wire                rst_n,

  input  wire                cmd_valid,
  output wire                cmd_ready,
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

  output wire                idle,

  output wire                bbo_bid_valid,
  output wire [PRICE_W-1:0]  bbo_bid_px,
  output wire [QTY_W-1:0]    bbo_bid_qty,
  output wire                bbo_ask_valid,
  output wire [PRICE_W-1:0]  bbo_ask_px,
  output wire [QTY_W-1:0]    bbo_ask_qty
);

  typedef enum logic [3:0] {
    ST_IDLE       = 4'd0,
    ST_ISSUE_REST = 4'd4,
    ST_WAIT_REST  = 4'd5,
    ST_DONE       = 4'd8
  } side_e;

  typedef enum logic [1:0] {
    LU_IDLE   = 2'd0,
    LU_DECIDE = 2'd1
  } lu_e;

  typedef enum logic [1:0] {
    MT_IDLE  = 2'd0,
    MT_ISSUE = 2'd1,
    MT_WAIT  = 2'd2,
    MT_HOLD  = 2'd3
  } mt_e;

  typedef enum logic [2:0] {
    WB_IDLE         = 3'd0,
    WB_FILL         = 3'd1,
    WB_ISSUE_REST   = 3'd2,
    WB_WAIT_REST    = 3'd3,
    WB_ISSUE_CANCEL = 3'd4,
    WB_WAIT_CANCEL  = 3'd5,
    WB_DONE         = 3'd6
  } wb_e;

  lu_e  lu_st;
  mt_e  mt_st;
  wb_e  wb_st;
  side_e bid_st, ask_st;

  logic [N_LEVELS-1:0] bid_used, ask_used;
  logic [PRICE_W-1:0]  bid_px [N_LEVELS];
  logic [PRICE_W-1:0]  ask_px [N_LEVELS];

  logic [N_LEVELS-1:0] bid_cmd_valid, ask_cmd_valid;
  logic [1:0]          bid_cmd_op [N_LEVELS];
  logic [1:0]          ask_cmd_op [N_LEVELS];
  logic [OID_W-1:0]    bid_fifo_oid, ask_fifo_oid;
  logic [QTY_W-1:0]    bid_fifo_qty, ask_fifo_qty;

  logic [N_LEVELS-1:0] bid_rsp_valid, ask_rsp_valid;
  logic [N_LEVELS-1:0] bid_rsp_ok, ask_rsp_ok;
  logic [OID_W-1:0]    bid_rsp_oid [N_LEVELS];
  logic [OID_W-1:0]    ask_rsp_oid [N_LEVELS];
  logic [QTY_W-1:0]    bid_rsp_qty [N_LEVELS];
  logic [QTY_W-1:0]    ask_rsp_qty [N_LEVELS];
  logic [N_LEVELS-1:0] bid_empty, ask_empty;
  logic [N_LEVELS-1:0] bid_full, ask_full;
  logic [QTY_W-1:0]    bid_total [N_LEVELS];
  logic [QTY_W-1:0]    ask_total [N_LEVELS];

  /* verilator lint_off UNUSEDSIGNAL */
  logic [N_LEVELS-1:0] bid_cmd_ready, ask_cmd_ready;
  logic [CNT_W-1:0]    bid_depth [N_LEVELS];
  logic [CNT_W-1:0]    ask_depth [N_LEVELS];
  logic [OID_W-1:0]    bid_head_oid [N_LEVELS];
  logic [OID_W-1:0]    ask_head_oid [N_LEVELS];
  logic [QTY_W-1:0]    bid_head_qty [N_LEVELS];
  logic [QTY_W-1:0]    ask_head_qty [N_LEVELS];
  /* verilator lint_on UNUSEDSIGNAL */

  genvar gi;
  generate
    for (gi = 0; gi < N_LEVELS; gi++) begin : gen_bid
      price_level_fifo u_bid (
        .clk, .rst_n,
        .cmd_valid (bid_cmd_valid[gi]),
        .cmd_ready (bid_cmd_ready[gi]),
        .cmd_op    (bid_cmd_op[gi]),
        .cmd_oid   (bid_fifo_oid),
        .cmd_qty   (bid_fifo_qty),
        .rsp_valid (bid_rsp_valid[gi]),
        .rsp_ok    (bid_rsp_ok[gi]),
        .rsp_oid   (bid_rsp_oid[gi]),
        .rsp_qty   (bid_rsp_qty[gi]),
        .empty     (bid_empty[gi]),
        .full      (bid_full[gi]),
        .depth     (bid_depth[gi]),
        .head_oid  (bid_head_oid[gi]),
        .head_qty  (bid_head_qty[gi]),
        .total_qty (bid_total[gi])
      );
    end
    for (gi = 0; gi < N_LEVELS; gi++) begin : gen_ask
      price_level_fifo u_ask (
        .clk, .rst_n,
        .cmd_valid (ask_cmd_valid[gi]),
        .cmd_ready (ask_cmd_ready[gi]),
        .cmd_op    (ask_cmd_op[gi]),
        .cmd_oid   (ask_fifo_oid),
        .cmd_qty   (ask_fifo_qty),
        .rsp_valid (ask_rsp_valid[gi]),
        .rsp_ok    (ask_rsp_ok[gi]),
        .rsp_oid   (ask_rsp_oid[gi]),
        .rsp_qty   (ask_rsp_qty[gi]),
        .empty     (ask_empty[gi]),
        .full      (ask_full[gi]),
        .depth     (ask_depth[gi]),
        .head_oid  (ask_head_oid[gi]),
        .head_qty  (ask_head_qty[gi]),
        .total_qty (ask_total[gi])
      );
    end
  endgenerate

  logic               bbo_bid_valid_c, bbo_ask_valid_c;
  logic [PRICE_W-1:0] bbo_bid_px_c, bbo_ask_px_c;
  logic [QTY_W-1:0]   bbo_bid_qty_c, bbo_ask_qty_c;
  logic [LVL_IDX_W-1:0] best_bid_idx, best_ask_idx;

  assign bbo_bid_valid = bbo_bid_valid_c;
  assign bbo_bid_px    = bbo_bid_px_c;
  assign bbo_bid_qty   = bbo_bid_qty_c;
  assign bbo_ask_valid = bbo_ask_valid_c;
  assign bbo_ask_px    = bbo_ask_px_c;
  assign bbo_ask_qty   = bbo_ask_qty_c;

  always_comb begin
    bbo_bid_valid_c = 1'b0;
    bbo_bid_px_c    = '0;
    bbo_bid_qty_c   = '0;
    best_bid_idx    = '0;
    bbo_ask_valid_c = 1'b0;
    bbo_ask_px_c    = '0;
    bbo_ask_qty_c   = '0;
    best_ask_idx    = '0;
    for (int i = 0; i < N_LEVELS; i++) begin
      if (bid_used[i] && !bid_empty[i]) begin
        if (!bbo_bid_valid_c || bid_px[i] > bbo_bid_px_c) begin
          bbo_bid_valid_c = 1'b1;
          bbo_bid_px_c    = bid_px[i];
          bbo_bid_qty_c   = bid_total[i];
          best_bid_idx    = LVL_IDX_W'(i);
        end
      end
      if (ask_used[i] && !ask_empty[i]) begin
        if (!bbo_ask_valid_c || ask_px[i] < bbo_ask_px_c) begin
          bbo_ask_valid_c = 1'b1;
          bbo_ask_px_c    = ask_px[i];
          bbo_ask_qty_c   = ask_total[i];
          best_ask_idx    = LVL_IDX_W'(i);
        end
      end
    end
  end

  logic               latched_side;
  logic [PRICE_W-1:0] latched_px;
  logic [OID_W-1:0]   latched_oid;
  logic [QTY_W-1:0]   remaining;
  logic [QTY_W-1:0]   filled_acc, rest_acc, unrested_acc;

  logic               match_is_ask;
  logic [LVL_IDX_W-1:0] match_idx;
  logic [PRICE_W-1:0] match_px;
  logic               rest_is_ask;
  logic [LVL_IDX_W-1:0] rest_idx_r;
  logic [QTY_W-1:0]   mt_hold_qty;
  logic [OID_W-1:0]   mt_hold_maker;

  logic [PRICE_W-1:0] bid_px_l, ask_px_l;
  logic [OID_W-1:0]   bid_oid_l, ask_oid_l;
  logic [QTY_W-1:0]   bid_qty_l, ask_qty_l;
  logic [QTY_W-1:0]   bid_rest_acc, ask_rest_acc;
  logic [QTY_W-1:0]   bid_unrested, ask_unrested;
  logic               bid_ok_l, ask_ok_l;
  logic [LVL_IDX_W-1:0] bid_rest_idx_r, ask_rest_idx_r;

  logic               rest_found, rest_alloc;
  logic [LVL_IDX_W-1:0] rest_idx;
  logic               rest_found_bid, rest_alloc_bid;
  logic [LVL_IDX_W-1:0] rest_idx_bid;
  logic               rest_found_ask, rest_alloc_ask;
  logic [LVL_IDX_W-1:0] rest_idx_ask;

  wire                 bid_lat_win, bid_lat_hit, ask_lat_win, ask_lat_hit;
  wire                 bid_l_win, bid_l_hit, ask_l_win, ask_l_hit;
  wire [LVL_IDX_W-1:0] bid_lat_slot, ask_lat_slot, bid_l_slot, ask_l_slot;

  level_table u_bid_latched (
    .used(bid_used), .px(bid_px), .probe(latched_px),
    .in_window(bid_lat_win), .hit(bid_lat_hit), .slot(bid_lat_slot)
  );
  level_table u_ask_latched (
    .used(ask_used), .px(ask_px), .probe(latched_px),
    .in_window(ask_lat_win), .hit(ask_lat_hit), .slot(ask_lat_slot)
  );
  level_table u_bid_rest (
    .used(bid_used), .px(bid_px), .probe(bid_px_l),
    .in_window(bid_l_win), .hit(bid_l_hit), .slot(bid_l_slot)
  );
  level_table u_ask_rest (
    .used(ask_used), .px(ask_px), .probe(ask_px_l),
    .in_window(ask_l_win), .hit(ask_l_hit), .slot(ask_l_slot)
  );

  always_comb begin
    rest_found = 1'b0;
    rest_alloc = 1'b0;
    rest_idx   = '0;
    if (latched_side == SIDE_BUY) begin
      if (bid_lat_hit) begin
        rest_found = 1'b1;
        rest_idx   = bid_lat_slot;
      end else if (bid_lat_win) begin
        for (int i = 0; i < N_LEVELS; i++) begin
          if (!rest_found && !bid_used[i]) begin
            rest_found = 1'b1;
            rest_alloc = 1'b1;
            rest_idx   = LVL_IDX_W'(i);
          end
        end
      end
    end else begin
      if (ask_lat_hit) begin
        rest_found = 1'b1;
        rest_idx   = ask_lat_slot;
      end else if (ask_lat_win) begin
        for (int i = 0; i < N_LEVELS; i++) begin
          if (!rest_found && !ask_used[i]) begin
            rest_found = 1'b1;
            rest_alloc = 1'b1;
            rest_idx   = LVL_IDX_W'(i);
          end
        end
      end
    end
  end

  always_comb begin
    rest_found_bid = 1'b0;
    rest_alloc_bid = 1'b0;
    rest_idx_bid   = '0;
    if (bid_l_hit) begin
      rest_found_bid = 1'b1;
      rest_idx_bid   = bid_l_slot;
    end else if (bid_l_win) begin
      for (int i = 0; i < N_LEVELS; i++) begin
        if (!rest_found_bid && !bid_used[i]) begin
          rest_found_bid = 1'b1;
          rest_alloc_bid = 1'b1;
          rest_idx_bid   = LVL_IDX_W'(i);
        end
      end
    end
  end

  always_comb begin
    rest_found_ask = 1'b0;
    rest_alloc_ask = 1'b0;
    rest_idx_ask   = '0;
    if (ask_l_hit) begin
      rest_found_ask = 1'b1;
      rest_idx_ask   = ask_l_slot;
    end else if (ask_l_win) begin
      for (int i = 0; i < N_LEVELS; i++) begin
        if (!rest_found_ask && !ask_used[i]) begin
          rest_found_ask = 1'b1;
          rest_alloc_ask = 1'b1;
          rest_idx_ask   = LVL_IDX_W'(i);
        end
      end
    end
  end

  wire bid_rest_busy = (bid_st != ST_IDLE);
  wire ask_rest_busy = (ask_st != ST_IDLE);
  wire lu_ready = (lu_st == LU_IDLE);
  wire mt_ready = (mt_st == MT_IDLE);
  wire wb_ready = (wb_st == WB_IDLE);
  wire taker_idle = lu_ready && mt_ready && wb_ready;
  wire both_idle  = (bid_st == ST_IDLE) && (ask_st == ST_IDLE) && taker_idle;
  wire wb_can_take_fill = wb_ready;

  assign idle = both_idle;

  wire crosses_bbo = (cmd_side == SIDE_BUY)
      ? (bbo_ask_valid_c && cmd_price >= bbo_ask_px_c)
      : (bbo_bid_valid_c && cmd_price <= bbo_bid_px_c);
  wire crosses_inflight = (cmd_side == SIDE_BUY)
      ? (ask_rest_busy && cmd_price >= ask_px_l)
      : (bid_rest_busy && cmd_price <= bid_px_l);
  wire would_cross = crosses_bbo || crosses_inflight;

  wire side_idle = (cmd_side == SIDE_BUY) ? (bid_st == ST_IDLE) : (ask_st == ST_IDLE);
  wire rest_ready = side_idle && taker_idle && !would_cross;

  assign cmd_ready = rst_n && (
      (cmd_op == BOOK_CANCEL) ? both_idle :
      (cmd_op == BOOK_LIMIT && would_cross) ? both_idle :
      (cmd_op == BOOK_LIMIT) ? rest_ready :
      both_idle);

  wire latched_crosses = (latched_side == SIDE_BUY)
      ? (bbo_ask_valid_c && latched_px >= bbo_ask_px_c)
      : (bbo_bid_valid_c && latched_px <= bbo_bid_px_c);

  wire rest_level_full = rest_found && !rest_alloc &&
      ((latched_side == SIDE_BUY) ? bid_full[rest_idx] : ask_full[rest_idx]);
  wire rest_full_bid = rest_found_bid && !rest_alloc_bid && bid_full[rest_idx_bid];
  wire rest_full_ask = rest_found_ask && !rest_alloc_ask && ask_full[rest_idx_ask];

  wire sel_rsp_valid = match_is_ask ? ask_rsp_valid[match_idx] : bid_rsp_valid[match_idx];
  wire sel_rsp_ok    = match_is_ask ? ask_rsp_ok[match_idx]    : bid_rsp_ok[match_idx];
  wire [OID_W-1:0] sel_rsp_oid = match_is_ask ? ask_rsp_oid[match_idx] : bid_rsp_oid[match_idx];
  wire [QTY_W-1:0] sel_rsp_qty = match_is_ask ? ask_rsp_qty[match_idx] : bid_rsp_qty[match_idx];
  wire sel_empty = match_is_ask ? ask_empty[match_idx] : bid_empty[match_idx];

  wire rest_rsp_valid = rest_is_ask ? ask_rsp_valid[rest_idx_r] : bid_rsp_valid[rest_idx_r];
  wire rest_rsp_ok    = rest_is_ask ? ask_rsp_ok[rest_idx_r]    : bid_rsp_ok[rest_idx_r];
  wire rest_empty     = rest_is_ask ? ask_empty[rest_idx_r]     : bid_empty[rest_idx_r];
  wire bid_rest_rsp_v = bid_rsp_valid[bid_rest_idx_r];
  wire bid_rest_rsp_ok = bid_rsp_ok[bid_rest_idx_r];
  wire bid_rest_empty = bid_empty[bid_rest_idx_r];
  wire ask_rest_rsp_v = ask_rsp_valid[ask_rest_idx_r];
  wire ask_rest_rsp_ok = ask_rsp_ok[ask_rest_idx_r];
  wire ask_rest_empty = ask_empty[ask_rest_idx_r];

  always_comb begin
    for (int i = 0; i < N_LEVELS; i++) begin
      bid_cmd_valid[i] = 1'b0;
      ask_cmd_valid[i] = 1'b0;
      bid_cmd_op[i]    = OP_NOP;
      ask_cmd_op[i]    = OP_NOP;
    end
    bid_fifo_oid = (!taker_idle) ? latched_oid : bid_oid_l;
    ask_fifo_oid = (!taker_idle) ? latched_oid : ask_oid_l;
    bid_fifo_qty = (!taker_idle) ? remaining   : bid_qty_l;
    ask_fifo_qty = (!taker_idle) ? remaining   : ask_qty_l;
    if (mt_st == MT_ISSUE) begin
      if (latched_side == SIDE_BUY) begin
        ask_cmd_valid[best_ask_idx] = 1'b1;
        ask_cmd_op[best_ask_idx]    = OP_MATCH;
      end else begin
        bid_cmd_valid[best_bid_idx] = 1'b1;
        bid_cmd_op[best_bid_idx]    = OP_MATCH;
      end
    end else if (wb_st == WB_ISSUE_REST) begin
      if (rest_found && !rest_level_full) begin
        if (latched_side == SIDE_BUY) begin
          bid_cmd_valid[rest_idx] = 1'b1;
          bid_cmd_op[rest_idx]    = OP_ADD;
        end else begin
          ask_cmd_valid[rest_idx] = 1'b1;
          ask_cmd_op[rest_idx]    = OP_ADD;
        end
      end
    end else if (wb_st == WB_ISSUE_CANCEL) begin
      bid_fifo_qty = '0;
      ask_fifo_qty = '0;
      for (int i = 0; i < N_LEVELS; i++) begin
        bid_cmd_valid[i] = 1'b1;
        ask_cmd_valid[i] = 1'b1;
        bid_cmd_op[i]    = OP_CANCEL;
        ask_cmd_op[i]    = OP_CANCEL;
      end
    end else begin
      if (bid_st == ST_ISSUE_REST && rest_found_bid && !rest_full_bid) begin
        bid_cmd_valid[rest_idx_bid] = 1'b1;
        bid_cmd_op[rest_idx_bid]    = OP_ADD;
      end
      if (ask_st == ST_ISSUE_REST && rest_found_ask && !rest_full_ask) begin
        ask_cmd_valid[rest_idx_ask] = 1'b1;
        ask_cmd_op[rest_idx_ask]    = OP_ADD;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      lu_st          <= LU_IDLE;
      mt_st          <= MT_IDLE;
      wb_st          <= WB_IDLE;
      bid_st         <= ST_IDLE;
      ask_st         <= ST_IDLE;
      bid_used       <= '0;
      ask_used       <= '0;
      for (int i = 0; i < N_LEVELS; i++) begin
        bid_px[i] <= '0;
        ask_px[i] <= '0;
      end
      latched_side   <= SIDE_BUY;
      latched_px     <= '0;
      latched_oid    <= '0;
      remaining      <= '0;
      filled_acc     <= '0;
      rest_acc       <= '0;
      unrested_acc   <= '0;
      match_is_ask   <= 1'b0;
      match_idx      <= '0;
      match_px       <= '0;
      rest_is_ask    <= 1'b0;
      rest_idx_r     <= '0;
      mt_hold_qty    <= '0;
      mt_hold_maker  <= '0;
      bid_px_l       <= '0;
      ask_px_l       <= '0;
      bid_oid_l      <= '0;
      ask_oid_l      <= '0;
      bid_qty_l      <= '0;
      ask_qty_l      <= '0;
      bid_rest_acc   <= '0;
      ask_rest_acc   <= '0;
      bid_unrested   <= '0;
      ask_unrested   <= '0;
      bid_ok_l       <= 1'b1;
      ask_ok_l       <= 1'b1;
      bid_rest_idx_r <= '0;
      ask_rest_idx_r <= '0;
      rsp_valid      <= 1'b0;
      rsp_ok         <= 1'b0;
      rsp_oid        <= '0;
      rsp_filled_qty <= '0;
      rsp_rest_qty   <= '0;
      rsp_unrested_qty <= '0;
      evt_valid      <= 1'b0;
      evt_maker_oid  <= '0;
      evt_taker_oid  <= '0;
      evt_price      <= '0;
      evt_qty        <= '0;
    end else begin
      rsp_valid <= 1'b0;
      if (evt_valid && !evt_ready) begin
        evt_valid <= 1'b1;
      end else begin
        evt_valid <= 1'b0;
      end

      if (cmd_valid && cmd_ready) begin
        if (cmd_op == BOOK_CANCEL) begin
          latched_side <= cmd_side;
          latched_px   <= cmd_price;
          latched_oid  <= cmd_oid;
          remaining    <= '0;
          filled_acc   <= '0;
          rest_acc     <= '0;
          unrested_acc <= '0;
          rsp_ok       <= 1'b1;
          wb_st        <= WB_ISSUE_CANCEL;
        end else if (cmd_op == BOOK_LIMIT && cmd_qty == '0) begin
          if (cmd_side == SIDE_BUY) begin
            bid_oid_l    <= cmd_oid;
            bid_ok_l     <= 1'b0;
            bid_rest_acc <= '0;
            bid_unrested <= '0;
            bid_st       <= ST_DONE;
          end else begin
            ask_oid_l    <= cmd_oid;
            ask_ok_l     <= 1'b0;
            ask_rest_acc <= '0;
            ask_unrested <= '0;
            ask_st       <= ST_DONE;
          end
        end else if (cmd_op == BOOK_LIMIT && would_cross) begin
          latched_side <= cmd_side;
          latched_px   <= cmd_price;
          latched_oid  <= cmd_oid;
          remaining    <= cmd_qty;
          filled_acc   <= '0;
          rest_acc     <= '0;
          unrested_acc <= '0;
          rsp_ok       <= 1'b1;
          mt_st        <= MT_ISSUE;
        end else if (cmd_op == BOOK_LIMIT && cmd_side == SIDE_BUY) begin
          bid_px_l     <= cmd_price;
          bid_oid_l    <= cmd_oid;
          bid_qty_l    <= cmd_qty;
          bid_ok_l     <= 1'b1;
          bid_rest_acc <= '0;
          bid_unrested <= '0;
          bid_st       <= ST_ISSUE_REST;
        end else if (cmd_op == BOOK_LIMIT && cmd_side == SIDE_SELL) begin
          ask_px_l     <= cmd_price;
          ask_oid_l    <= cmd_oid;
          ask_qty_l    <= cmd_qty;
          ask_ok_l     <= 1'b1;
          ask_rest_acc <= '0;
          ask_unrested <= '0;
          ask_st       <= ST_ISSUE_REST;
        end else begin
          latched_oid  <= cmd_oid;
          filled_acc   <= '0;
          rest_acc     <= '0;
          unrested_acc <= '0;
          rsp_ok       <= 1'b0;
          wb_st        <= WB_DONE;
        end
      end

      unique case (lu_st)
        LU_IDLE: begin
        end
        LU_DECIDE: begin
          if (remaining == '0) begin
            if (wb_ready) begin
              wb_st <= WB_DONE;
              lu_st <= LU_IDLE;
            end
          end else if (latched_crosses) begin
            if (mt_ready) begin
              mt_st <= MT_ISSUE;
              lu_st <= LU_IDLE;
            end
          end else if (wb_ready) begin
            wb_st <= WB_ISSUE_REST;
            lu_st <= LU_IDLE;
          end
        end
        default: lu_st <= LU_IDLE;
      endcase

      unique case (mt_st)
        MT_IDLE: begin
        end
        MT_ISSUE: begin
          match_is_ask <= (latched_side == SIDE_BUY);
          if (latched_side == SIDE_BUY) begin
            match_idx <= best_ask_idx;
            match_px  <= bbo_ask_px_c;
          end else begin
            match_idx <= best_bid_idx;
            match_px  <= bbo_bid_px_c;
          end
          mt_st <= MT_WAIT;
        end
        MT_WAIT: begin
          if (sel_rsp_valid) begin
            if (sel_rsp_ok) begin
              remaining     <= remaining - sel_rsp_qty;
              filled_acc    <= filled_acc + sel_rsp_qty;
              mt_hold_qty   <= sel_rsp_qty;
              mt_hold_maker <= sel_rsp_oid;
              if (sel_empty) begin
                if (match_is_ask) ask_used[match_idx] <= 1'b0;
                else              bid_used[match_idx] <= 1'b0;
              end
              mt_st <= MT_HOLD;
            end else begin
              rsp_ok    <= 1'b0;
              remaining <= '0;
              mt_st     <= MT_IDLE;
              lu_st     <= LU_DECIDE;
            end
          end
        end
        MT_HOLD: begin
          if (wb_can_take_fill) begin
            evt_valid     <= 1'b1;
            evt_maker_oid <= mt_hold_maker;
            evt_taker_oid <= latched_oid;
            evt_price     <= match_px;
            evt_qty       <= mt_hold_qty;
            wb_st         <= WB_FILL;
            mt_st         <= MT_IDLE;
            lu_st         <= LU_DECIDE;
          end
        end
        default: mt_st <= MT_IDLE;
      endcase

      unique case (wb_st)
        WB_IDLE: begin
        end
        WB_FILL: begin
          evt_valid <= 1'b1;
          if (evt_ready) begin
            evt_valid <= 1'b0;
            wb_st     <= WB_IDLE;
          end
        end
        WB_ISSUE_REST: begin
          if (!rest_found || rest_level_full) begin
            unrested_acc <= remaining;
            rsp_ok       <= 1'b0;
            wb_st        <= WB_DONE;
          end else begin
            rest_idx_r  <= rest_idx;
            rest_is_ask <= (latched_side == SIDE_SELL);
            if (rest_alloc) begin
              if (latched_side == SIDE_BUY) begin
                bid_used[rest_idx] <= 1'b1;
                bid_px[rest_idx]   <= latched_px;
              end else begin
                ask_used[rest_idx] <= 1'b1;
                ask_px[rest_idx]   <= latched_px;
              end
            end
            wb_st <= WB_WAIT_REST;
          end
        end
        WB_WAIT_REST: begin
          if (rest_rsp_valid) begin
            if (rest_rsp_ok) begin
              rest_acc <= remaining;
            end else begin
              unrested_acc <= remaining;
              rsp_ok       <= 1'b0;
              if (rest_empty) begin
                if (rest_is_ask) ask_used[rest_idx_r] <= 1'b0;
                else             bid_used[rest_idx_r] <= 1'b0;
              end
            end
            wb_st <= WB_DONE;
          end
        end
        WB_ISSUE_CANCEL: begin
          wb_st <= WB_WAIT_CANCEL;
        end
        WB_WAIT_CANCEL: begin
          rsp_ok   <= 1'b0;
          rest_acc <= '0;
          for (int i = 0; i < N_LEVELS; i++) begin
            if (bid_rsp_valid[i] && bid_rsp_ok[i]) begin
              rsp_ok   <= 1'b1;
              rest_acc <= bid_rsp_qty[i];
              if (bid_empty[i]) bid_used[i] <= 1'b0;
            end
            if (ask_rsp_valid[i] && ask_rsp_ok[i]) begin
              rsp_ok   <= 1'b1;
              rest_acc <= ask_rsp_qty[i];
              if (ask_empty[i]) ask_used[i] <= 1'b0;
            end
          end
          wb_st <= WB_DONE;
        end
        WB_DONE: begin
          rsp_valid        <= 1'b1;
          rsp_oid          <= latched_oid;
          rsp_filled_qty   <= filled_acc;
          rsp_rest_qty     <= rest_acc;
          rsp_unrested_qty <= unrested_acc;
          wb_st            <= WB_IDLE;
        end
        default: wb_st <= WB_IDLE;
      endcase

      unique case (bid_st)
        ST_IDLE: begin
        end
        ST_ISSUE_REST: begin
          if (!rest_found_bid || rest_full_bid) begin
            bid_unrested <= bid_qty_l;
            bid_ok_l     <= 1'b0;
            bid_st       <= ST_DONE;
          end else begin
            bid_rest_idx_r <= rest_idx_bid;
            if (rest_alloc_bid) begin
              bid_used[rest_idx_bid] <= 1'b1;
              bid_px[rest_idx_bid]   <= bid_px_l;
            end
            bid_st <= ST_WAIT_REST;
          end
        end
        ST_WAIT_REST: begin
          if (bid_rest_rsp_v) begin
            if (bid_rest_rsp_ok) begin
              bid_rest_acc <= bid_qty_l;
            end else begin
              bid_unrested <= bid_qty_l;
              bid_ok_l     <= 1'b0;
              if (bid_rest_empty) bid_used[bid_rest_idx_r] <= 1'b0;
            end
            bid_st <= ST_DONE;
          end
        end
        ST_DONE: begin
          if (wb_st != WB_DONE) begin
            rsp_valid        <= 1'b1;
            rsp_ok           <= bid_ok_l;
            rsp_oid          <= bid_oid_l;
            rsp_filled_qty   <= '0;
            rsp_rest_qty     <= bid_rest_acc;
            rsp_unrested_qty <= bid_unrested;
            bid_st           <= ST_IDLE;
          end
        end
        default: bid_st <= ST_IDLE;
      endcase

      unique case (ask_st)
        ST_IDLE: begin
        end
        ST_ISSUE_REST: begin
          if (!rest_found_ask || rest_full_ask) begin
            ask_unrested <= ask_qty_l;
            ask_ok_l     <= 1'b0;
            ask_st       <= ST_DONE;
          end else begin
            ask_rest_idx_r <= rest_idx_ask;
            if (rest_alloc_ask) begin
              ask_used[rest_idx_ask] <= 1'b1;
              ask_px[rest_idx_ask]   <= ask_px_l;
            end
            ask_st <= ST_WAIT_REST;
          end
        end
        ST_WAIT_REST: begin
          if (ask_rest_rsp_v) begin
            if (ask_rest_rsp_ok) begin
              ask_rest_acc <= ask_qty_l;
            end else begin
              ask_unrested <= ask_qty_l;
              ask_ok_l     <= 1'b0;
              if (ask_rest_empty) ask_used[ask_rest_idx_r] <= 1'b0;
            end
            ask_st <= ST_DONE;
          end
        end
        ST_DONE: begin
          if (wb_st != WB_DONE && bid_st != ST_DONE) begin
            rsp_valid        <= 1'b1;
            rsp_ok           <= ask_ok_l;
            rsp_oid          <= ask_oid_l;
            rsp_filled_qty   <= '0;
            rsp_rest_qty     <= ask_rest_acc;
            rsp_unrested_qty <= ask_unrested;
            ask_st           <= ST_IDLE;
          end
        end
        default: ask_st <= ST_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
