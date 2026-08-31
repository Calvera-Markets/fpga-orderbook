`ifndef EXCH_PKG_SV
`define EXCH_PKG_SV

package exch_pkg;
  localparam int OID_W      = 64;
  localparam int QTY_W      = 32;
  localparam int MAX_ORDERS = 16;
  localparam int IDX_W      = $clog2(MAX_ORDERS);
  localparam int CNT_W      = $clog2(MAX_ORDERS + 1);

  localparam logic [1:0] OP_ADD    = 2'd0;
  localparam logic [1:0] OP_MATCH  = 2'd1;
  localparam logic [1:0] OP_CANCEL = 2'd2;
  localparam logic [1:0] OP_NOP    = 2'd3;

  typedef struct packed {
    logic             valid;
    logic [OID_W-1:0] oid;
    logic [QTY_W-1:0] qty;
  } order_entry_t;
endpackage

`endif
