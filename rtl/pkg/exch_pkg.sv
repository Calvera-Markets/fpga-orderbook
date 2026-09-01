`ifndef EXCH_PKG_SV
`define EXCH_PKG_SV

// Shared widths/opcodes. A given module will not use every name.
/* verilator lint_off UNUSEDPARAM */
package exch_pkg;
  localparam int OID_W      = 64;
  localparam int QTY_W      = 32;
  localparam int PRICE_W    = 32;
  localparam int SYMBOL_W   = 16;
  localparam int MAX_ORDERS = 16;
  localparam int IDX_W      = $clog2(MAX_ORDERS);
  localparam int CNT_W      = $clog2(MAX_ORDERS + 1);
  localparam int N_LEVELS   = 8;
  localparam int LVL_IDX_W  = $clog2(N_LEVELS);
  localparam int N_PIPES    = 8;
  localparam int PIPE_W     = $clog2(N_PIPES);
  localparam int N_SYMS_PER_PIPE = 16;
  localparam int SYM_IDX_W  = $clog2(N_SYMS_PER_PIPE);

  localparam logic [1:0] OP_ADD    = 2'd0;
  localparam logic [1:0] OP_MATCH  = 2'd1;
  localparam logic [1:0] OP_CANCEL = 2'd2;
  localparam logic [1:0] OP_NOP    = 2'd3;

  localparam logic BOOK_LIMIT  = 1'b0;
  localparam logic BOOK_CANCEL = 1'b1;
  localparam logic SIDE_BUY    = 1'b0;
  localparam logic SIDE_SELL   = 1'b1;

  typedef struct packed {
    logic             valid;
    logic [OID_W-1:0] oid;
    logic [QTY_W-1:0] qty;
  } order_entry_t;
endpackage
/* verilator lint_on UNUSEDPARAM */

`endif
