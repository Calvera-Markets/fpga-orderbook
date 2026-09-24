`default_nettype none

// Sequence check, then the order word. A reject never reaches a slice port.
module frame_top
  import exch_pkg::*;
#(
  parameter int N = 4
) (
  input  wire                clk,
  input  wire                rst_n,

  input  wire                word_valid,
  output wire                word_ready,
  input  wire [7:0]          word_session,
  input  wire [31:0]         word_seq,
  input  wire                word_kill,
  input  wire [1:0]         word_op,
  input  wire                word_side,
  input  wire [SYMBOL_W-1:0] word_symbol,
  input  wire [PRICE_W-1:0]  word_price,
  input  wire [QTY_W-1:0]    word_qty,
  input  wire [OID_W-1:0]    word_oid,

  output wire [N-1:0]        cmd_valid,
  input  wire [N-1:0]        cmd_ready,
  output wire [N-1:0]        cmd_op,
  output wire [N-1:0]        cmd_side,
  output wire [PRICE_W-1:0]  cmd_price [N],
  output wire [QTY_W-1:0]    cmd_qty [N],
  output wire [OID_W-1:0]    cmd_oid [N],

  output wire                reject_valid,
  output wire [7:0]          reject_reason,
  output wire [OID_W-1:0]    reject_oid
);

  wire risk_pass;
  wire risk_reject;
  wire [7:0] risk_reason;
  wire seq_pass;
  wire seq_reject;
  wire [7:0] seq_reason;

  risk_kill u_risk (
    .clk, .rst_n,
    .valid   (word_valid),
    .session (word_session),
    .qty     (word_qty),
    .kill    (word_kill),
    .pass    (risk_pass),
    .reject  (risk_reject),
    .reason  (risk_reason)
  );
  wire frame_ready;
  wire frame_reject;
  wire [7:0] frame_reason;
  /* verilator lint_off UNUSEDSIGNAL */
  wire [OID_W-1:0] frame_rej_oid;
  wire fired_unused;
  /* verilator lint_on UNUSEDSIGNAL */

  order_frame #(.N(N)) u_frame (
    .clk, .rst_n,
    .word_valid  (word_valid && risk_pass && seq_pass),
    .word_ready  (frame_ready),
    .word_op, .word_side, .word_symbol, .word_price, .word_qty, .word_oid,
    .cmd_valid, .cmd_ready, .cmd_op, .cmd_side, .cmd_price, .cmd_qty, .cmd_oid,
    .reject_valid (frame_reject),
    .reject_reason(frame_reason),
    .reject_oid   (frame_rej_oid),
    .fired        (fired_unused)
  );

  session_table u_seq (
    .clk, .rst_n,
    .valid   (word_valid && risk_pass),
    .take    (|cmd_valid),
    .session (word_session),
    .seq     (word_seq),
    .pass    (seq_pass),
    .reject  (seq_reject),
    .reason  (seq_reason)
  );

  assign word_ready    = frame_ready;
  assign reject_valid  = risk_reject || seq_reject || frame_reject;
  assign reject_reason = risk_reject ? risk_reason : seq_reject ? seq_reason : frame_reason;
  assign reject_oid    = word_oid;

endmodule

`default_nettype wire
