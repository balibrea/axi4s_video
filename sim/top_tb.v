
module top_tb;

  // Parameters
  localparam  VIDEOC_W = 8;
  localparam  TDATA_WIDTH = 32;

  //Ports
  reg  aclk;
  reg  arst_n;
  wire [VIDEOC_W-1 : 0] red;
  wire [VIDEOC_W-1 : 0] green;
  wire [VIDEOC_W-1 : 0] blue;
  wire [9 : 0] sx_o;
  wire [9 : 0] sy_o;
  wire de_o;
  wire hsync_o;
  wire vsync_o;

  top # (
    .VIDEOC_W(VIDEOC_W),
    .TDATA_WIDTH(TDATA_WIDTH)
  )
  top_inst (
    .aclk(aclk),
    .arst_n(arst_n),
    .red(red),
    .green(green),
    .blue(blue),
    .sx_o(sx_o),
    .sy_o(sy_o),
    .de_o(de_o),
    .hsync_o(hsync_o),
    .vsync_o(vsync_o)
  );

always #5  aclk = ! aclk ;

// ====================================================================
//  Checkers de protocolo AXI4-Stream Video
//
//  El slave no usa tlast ni tuser (mismo reloj, mismo reset, sin FIFO:
//  master y slave quedan enganchados por tready). Estos bloques los
//  vigilan igual, porque m_axis.v va a la FPGA y ahi si los consumen
//  IPs que esperan un stream de video valido.
//
//  Alcance de las comprobaciones:
//    - tlast cada H_RES beats calificados  (fin de linea)
//    - tuser cada H_RES*V_RES beats        (inicio de frame)
//    - tuser solo en el primer beat del frame
// ====================================================================

  localparam integer H_RES = 640;   // deben coincidir con los de top.v
  localparam integer V_RES = 480;

  // Acceso jerarquico al stream interno de top
  wire chk_tvalid = top_inst.m_axis_tvalid;
  wire chk_tready = top_inst.m_axis_tready;
  wire chk_tlast  = top_inst.m_axis_tlast;
  wire chk_tuser  = top_inst.m_axis_tuser;

  // Un beat solo cuenta cuando hay handshake
  wire beat = chk_tvalid && chk_tready;

  integer pix_in_line = 0;   // beats desde el ultimo tlast
  integer line_in_frm = 0;   // lineas completadas desde el ultimo tuser
  integer beats_in_frm = 0;  // beats desde el ultimo tuser
  integer sof_seen    = 0;   // cuantos SOF van
  integer err_count   = 0;

  always @(posedge aclk) begin
    if (!arst_n) begin
      pix_in_line  <= 0;
      line_in_frm  <= 0;
      beats_in_frm <= 0;
      sof_seen     <= 0;
    end else if (beat) begin

      // ---- tuser: solo en el primer pixel de la primera linea del frame ----
      if (chk_tuser && pix_in_line != 0) begin
        $display("[PROTO] t=%0t  tuser en el pixel %0d de la linea, esperado 0",
                 $time, pix_in_line);
        err_count = err_count + 1;
      end

      // A partir del segundo SOF se puede medir el frame anterior:
      // debe haber traido exactamente H_RES*V_RES beats y V_RES lineas.
      if (chk_tuser && sof_seen > 0 && beats_in_frm != H_RES*V_RES) begin
        $display("[PROTO] t=%0t  frame de %0d beats, esperado %0d",
                 $time, beats_in_frm, H_RES*V_RES);
        err_count = err_count + 1;
      end

      if (chk_tuser && sof_seen > 0 && line_in_frm != V_RES) begin
        $display("[PROTO] t=%0t  frame de %0d lineas, esperado %0d",
                 $time, line_in_frm, V_RES);
        err_count = err_count + 1;
      end

      // ---- frame demasiado largo: se paso de un frame sin ver tuser ----
      if (!chk_tuser && sof_seen > 0 && beats_in_frm >= H_RES*V_RES) begin
        $display("[PROTO] t=%0t  frame supera %0d beats sin tuser",
                 $time, H_RES*V_RES);
        err_count = err_count + 1;
      end

      // ---- tlast: debe caer exactamente en el pixel H_RES-1 ----
      if (chk_tlast && pix_in_line != H_RES-1) begin
        $display("[PROTO] t=%0t  tlast en el pixel %0d, esperado %0d",
                 $time, pix_in_line, H_RES-1);
        err_count = err_count + 1;
      end

      // ---- linea demasiado larga: se paso de H_RES sin tlast ----
      if (!chk_tlast && pix_in_line >= H_RES-1) begin
        $display("[PROTO] t=%0t  linea supera %0d pixeles sin tlast",
                 $time, H_RES);
        err_count = err_count + 1;
      end

      // ---------------- actualizacion de contadores ----------------
      if (chk_tuser) begin
        beats_in_frm <= 1;              // este beat ya cuenta para el frame nuevo
        sof_seen     <= sof_seen + 1;
      end else begin
        beats_in_frm <= beats_in_frm + 1;
      end

      if (chk_tlast) begin
        pix_in_line <= 0;
        line_in_frm <= chk_tuser ? 1 : line_in_frm + 1;
      end else begin
        pix_in_line <= pix_in_line + 1;
        if (chk_tuser) line_in_frm <= 0;
      end
    end
  end

initial begin
    $dumpfile("top_tb.vcd");
    $dumpvars(0, top_tb);

    aclk = 1'b0;
    arst_n = 1'b0;
    #100;
    arst_n = 1'b1;
    #9000000;   // ~900k ciclos: mas de 2 frames completos

    $display("========================================");
    $display(" SOF detectados=%0d", sof_seen);
    if (err_count == 0)
      $display(" Protocolo AXIS-Video: OK (sin errores)");
    else
      $display(" Protocolo AXIS-Video: %0d ERROR(ES)", err_count);
    $display("========================================");
    $finish;
end

endmodule
