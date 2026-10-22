// Timed Cheats: on-screen elapsed-time overlay + cheat tier gating
// "For fun" SNES_MiSTer fork feature.
//
// - Keeps a real-time elapsed seconds counter (clk_sys / clk_rate -> 1Hz tick),
//   started the first time the OSD menu is closed after a game loads.
// - Renders an MM:SS digit overlay in the bottom-right corner of the core's
//   native active video area (so it stays inside the 4:3-safe region even
//   when the final output is stretched to 16:9).
// - Produces a 32-bit gate mask consumed by the cheat engine (CODES module
//   in cheatcodes.sv): the first 2^split_sel loaded cheats are always allowed
//   to fire ("immediate" tier); the remaining ones are held back until
//   delay_sel minutes have elapsed ("timed" tier).

module osd_timer
(
	input         clk_video,
	input         ce_pix,
	input         HBlank,
	input         VBlank,
	input         hires,          // double glyph pixel size for hi-res modes

	input         clk_sys,
	input  [31:0] clk_rate,       // clk_sys ticks per real second
	input         reset,          // pulses on core reset / new game load
	input         game_loaded,    // 1 once a cart is present
	input         osd_status,     // 1 while the MiSTer OSD menu is open

	input         show_timer,     // OSD: on-screen timer display on/off
	input         timed_cheats_en,// OSD: timed cheat tiers on/off
	input  [2:0]  delay_sel,      // OSD: 0=5s,1=10s,2=30s,3=1m,4=5m,5=10m,6=15m,7=20m
	input         split_sel,      // OSD: 0=first 1, 1=first 2 immediate cheats
	input         cycle_en,       // OSD: alternate timed tier on/off every delay_sel period

	input  [7:0]  R_in,
	input  [7:0]  G_in,
	input  [7:0]  B_in,
	output [7:0]  R_out,
	output [7:0]  G_out,
	output [7:0]  B_out,

	output [31:0] timed_gate
);

/////////////////////// real-time seconds counter ///////////////////////

reg        timer_running;
reg        old_osd_status;
reg [31:0] tickdiv;
reg [16:0] timer_sec; // up to ~36h, plenty

always @(posedge clk_sys) begin
	old_osd_status <= osd_status;

	if (reset || !game_loaded) begin
		timer_running <= 0;
		timer_sec     <= 0;
		tickdiv       <= 0;
	end
	else begin
		// Start counting the first time the OSD closes after a load.
		if (old_osd_status && !osd_status) timer_running <= 1;

		if (timer_running) begin
			if (tickdiv >= clk_rate - 1'd1) begin
				tickdiv <= 0;
				if (timer_sec < 17'd99999) timer_sec <= timer_sec + 1'd1;
			end
			else tickdiv <= tickdiv + 1'd1;
		end
	end
end

wire [6:0] secs_val = timer_sec % 60;
wire [6:0] mins_val = (timer_sec / 60 > 99) ? 7'd99 : (timer_sec / 60);

/////////////////////// timed-cheat tier gate ///////////////////////

reg [31:0] delay_sec;
always @(*) begin
	case (delay_sel)
		3'd0: delay_sec = 32'd5;    // 5 sec
		3'd1: delay_sec = 32'd10;   // 10 sec
		3'd2: delay_sec = 32'd30;   // 30 sec
		3'd3: delay_sec = 32'd60;   // 1 min
		3'd4: delay_sec = 32'd300;  // 5 min
		3'd5: delay_sec = 32'd600;  // 10 min
		3'd6: delay_sec = 32'd900;  // 15 min
		3'd7: delay_sec = 32'd1200; // 20 min
	endcase
end

// Unlocks permanently once elapsed; cycle_en then alternates the tier
// on/off every `delay_sec` seconds after that first unlock, instead of
// staying on forever.
wire       tier_unlocked = (timer_sec >= delay_sec);

reg [31:0] cycle_phase;
always @(posedge clk_sys) begin
	if (reset || !game_loaded || !tier_unlocked) begin
		cycle_phase <= 0;
	end
	else if (timer_running && tickdiv >= clk_rate - 1'd1) begin
		if (cycle_phase >= (delay_sec << 1) - 1'd1) cycle_phase <= 0;
		else cycle_phase <= cycle_phase + 1'd1;
	end
end

wire       cycle_active = !cycle_en || (cycle_phase < delay_sec);
wire       tier_elapsed = tier_unlocked && cycle_active;
wire [7:0] split_n = split_sel ? 8'd2 : 8'd1; // first 1 or first 2 cheats always on

reg [31:0] gate_mask;
integer gi;
always @(*) begin
	for (gi = 0; gi < 32; gi = gi + 1)
		gate_mask[gi] = (!timed_cheats_en) ? 1'b1
			: (gi < split_n) ? 1'b1
			: tier_elapsed;
end

assign timed_gate = gate_mask;

/////////////////////// cross to video clock domain ///////////////////////

reg [6:0] mins_v0, mins_v1, secs_v0, secs_v1;
always @(posedge clk_video) begin
	mins_v0 <= mins_val; mins_v1 <= mins_v0;
	secs_v0 <= secs_val; secs_v1 <= secs_v0;
end

/////////////////////// active frame dimension tracking ///////////////////////

reg [9:0] hcnt, vcnt;
reg [9:0] frame_w, frame_h;
reg       hb_d, vb_d;

always @(posedge clk_video) begin
	hb_d <= HBlank;
	vb_d <= VBlank;

	if (HBlank) begin
		if (!hb_d) frame_w <= hcnt;
		hcnt <= 0;
	end
	else if (ce_pix) hcnt <= hcnt + 1'd1;

	if (VBlank) begin
		if (!vb_d) frame_h <= vcnt;
		vcnt <= 0;
	end
	else if (hb_d & ~HBlank) vcnt <= vcnt + 1'd1;
end

/////////////////////// glyph font: 3x5, digits 0-9 and ':' ///////////////////////

function [2:0] font_row(input [3:0] ch, input [2:0] row);
	reg [14:0] bits; // 5 rows x 3 bits, MSB = top row
	begin
		case (ch)
			4'd0: bits = 15'b111_101_101_101_111;
			4'd1: bits = 15'b010_110_010_010_111;
			4'd2: bits = 15'b111_001_111_100_111;
			4'd3: bits = 15'b111_001_111_001_111;
			4'd4: bits = 15'b101_101_111_001_001;
			4'd5: bits = 15'b111_100_111_001_111;
			4'd6: bits = 15'b111_100_111_101_111;
			4'd7: bits = 15'b111_001_010_010_010;
			4'd8: bits = 15'b111_101_111_101_111;
			4'd9: bits = 15'b111_101_111_001_111;
			default: bits = 15'b010_010_000_010_010; // colon ':' uses only center column
		endcase
		font_row = bits[(4-row)*3 +: 3];
	end
endfunction

/////////////////////// overlay placement + render ///////////////////////

// 5 glyphs (MM:SS), 3px wide + 1px gap each, doubled when hires.
localparam GLYPH_W = 3;
localparam GLYPH_H = 5;
localparam GLYPH_GAP = 1;
localparam N_GLYPHS = 5;

wire [3:0] scale = hires ? 4'd2 : 4'd1;
wire [9:0] cell_w = (GLYPH_W + GLYPH_GAP) * scale;
wire [9:0] box_w  = cell_w * N_GLYPHS;
wire [9:0] box_h  = GLYPH_H * scale * 2; // extra vertical scale for visibility

wire [9:0] margin_x = frame_w >> 4; // ~6.25% inset
wire [9:0] margin_y = frame_h >> 4;

wire [9:0] box_x0 = (frame_w > (box_w + margin_x)) ? (frame_w - box_w - margin_x) : 0;
wire [9:0] box_y0 = (frame_h > (box_h + margin_y)) ? (frame_h - box_h - margin_y) : 0;

wire overlay_active = show_timer && !HBlank && !VBlank &&
                       (hcnt >= box_x0) && (hcnt < box_x0 + box_w) &&
                       (vcnt >= box_y0) && (vcnt < box_y0 + box_h);

reg overlay_pixel;
always @(*) begin
	overlay_pixel = 0;
	if (overlay_active) begin
		reg [9:0] rel_x, rel_y;
		reg [2:0] glyph_idx;
		reg [9:0] gx;
		reg [2:0] px, py;
		reg [3:0] ch;

		rel_x = hcnt - box_x0;
		rel_y = vcnt - box_y0;
		// cell_w is always 4 (lores) or 8 (hires); avoid variable divide/mul in synthesis
		glyph_idx = hires ? (rel_x >> 3) : (rel_x >> 2);
		gx = rel_x - (hires ? ({glyph_idx, 3'b0}) : ({glyph_idx, 2'b0}));
		px = hires ? (gx >> 1) : gx[2:0];
		py = hires ? (rel_y >> 2) : (rel_y >> 1); // vertical scale x2 extra

		case (glyph_idx)
			0: ch = mins_v1 / 10;
			1: ch = mins_v1 % 10;
			2: ch = 4'd10; // colon
			3: ch = secs_v1 / 10;
			4: ch = secs_v1 % 10;
			default: ch = 4'd0;
		endcase

		if (px < GLYPH_W && py < GLYPH_H) begin
			reg [2:0] row_bits;
			row_bits = font_row(ch, py);
			overlay_pixel = row_bits[GLYPH_W-1-px];
		end
	end
end

assign R_out = overlay_pixel ? 8'hFF : R_in;
assign G_out = overlay_pixel ? 8'hFF : G_in;
assign B_out = overlay_pixel ? 8'h40 : B_in;

endmodule
