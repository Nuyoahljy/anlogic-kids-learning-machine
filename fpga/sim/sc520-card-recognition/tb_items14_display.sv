`timescale 1ns/1ps
module tb_items14_display;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [10:0] pixel_x=0;
    reg [9:0] pixel_y=0;
    reg [2:0] line_index=0;
    reg [5:0] char_index=0;
    reg [1:0] mode=1,phase=1;
    reg [3:0] score=2,question_index=3,target_item=14,display_item=10;
    reg [2:0] feedback=0;
    reg source_test=0,armed=1,audio_fault=0,audio_busy=0,result_healthy=1;
    wire [7:0] glyph;
    wire [1:0] tone;
    wire active;
    wire [23:0] rgb;
    reg [7:0] rom_glyph=0;
    reg [3:0] rom_row=0;
    wire [15:0] rom_bits;
    integer errors=0,checks=0,scenarios=0,injected=0;
    integer inject_fault=0,ignored;
    reg test_done=0;
    integer i,j,k,x,y,g,row;
    reg [15:0] old_bits,expected_bits;
    reg [255:0] bitmap;
    reg [7:0] expected [0:7][0:63];
    reg [1:0] expected_tone [0:7];

    // Both includes are copied to the runner's input snapshot and added to
    // +incdir. Their values come from manifest text and full font bitmaps.
    `include "items14_text_reference.svh"
    `include "items14_bitmap_reference.svh"

    items14_content content_dut(.line_index(line_index),.char_index(char_index),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),
        .target_item(target_item),.display_item(display_item),.feedback(feedback),
        .source_test(source_test),.armed(armed),.audio_fault(audio_fault),.audio_busy(audio_busy),
        .result_healthy(result_healthy),.glyph(glyph),.tone(tone));
    items14_osd osd_dut(.clk(clk),.rst_n(rst_n),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),
        .target_item(target_item),.display_item(display_item),.feedback(feedback),
        .source_test(source_test),.armed(armed),.audio_fault(audio_fault),.audio_busy(audio_busy),
        .result_healthy(result_healthy),.active(active),.rgb(rgb));
    items14_font_rom rom_dut(.clk(clk),.glyph(rom_glyph),.row(rom_row),.bits(rom_bits));

    task automatic ck(input bit condition,input string message);
        begin
            checks=checks+1;
            if(!condition) begin
                errors=errors+1;
                if(errors<=30) $display("FAIL display scenario=%0d x=%0d y=%0d line=%0d col=%0d: %s",scenarios,pixel_x,pixel_y,line_index,char_index,message);
            end
        end
    endtask
    task automatic start_case(input string name);
        begin scenarios=scenarios+1; $display("CASE display %0d %s",scenarios,name); end
    endtask
    task automatic clear_line(input integer line_no);
        integer col;
        begin
            for(col=0;col<64;col=col+1) expected[line_no][col]=0;
            expected_tone[line_no]=0;
        end
    endtask
    task automatic text_at(input integer line_no,input integer first,input integer text_id);
        integer col;
        begin
            for(col=0;col<64-first;col=col+1)
                expected[line_no][first+col]=items14_ref_text(text_id,col);
        end
    endtask
    task automatic object_at(input integer line_no,input integer first,input integer item);
        integer col;
        begin
            for(col=0;col<64-first;col=col+1)
                expected[line_no][first+col]=items14_ref_item(item,col);
        end
    endtask
    task automatic explore_expected(input integer item);
        integer line_no;
        begin
            for(line_no=0;line_no<8;line_no=line_no+1) clear_line(line_no);
            // Literal fixed-header positions from the presentation specification.
            text_at(0,0,2); text_at(0,6,5); text_at(0,17,6);
            expected[0][9]=45; expected[0][10]=45;
            expected[0][11]=47; expected[0][12]=49; expected[0][13]=48;
            expected[0][20]=48; expected[0][21]=50;
            expected[0][22]=47; expected[0][23]=49; expected[0][24]=48;
            expected_tone[0]=1;
            text_at(1,0,8); expected_tone[1]=1;
            text_at(2,0,9); text_at(3,0,13); text_at(4,0,24);
            text_at(5,0,25); object_at(5,5,item);
        end
    endtask
    task automatic quiz_expected(input integer target,input integer detected);
        begin
            explore_expected(detected);
            // Replace only the four title characters; preserve the header.
            for(integer col=0;col<4;col=col+1) expected[0][col]=items14_ref_text(3,col);
            expected[0][9]=48; expected[0][10]=51;
            clear_line(3); text_at(3,0,14); object_at(3,4,target); expected_tone[3]=1;
            clear_line(4); text_at(4,0,22);
        end
    endtask
    task automatic check_content;
        integer line_no,col;
        begin
            for(line_no=0;line_no<8;line_no=line_no+1)
                for(col=0;col<64;col=col+1) begin
                    line_index=line_no; char_index=col; #1;
                    ck(glyph===expected[line_no][col],"manifest glyph and trailing blank");
                    ck(tone===expected_tone[line_no],"text tone");
                end
        end
    endtask
    task automatic sample_pixel(input integer px,input integer py);
        reg previous_active,want_active,ink_pixel;
        reg [23:0] previous_rgb,want_rgb,ink;
        reg [255:0] full_bitmap;
        integer line_no,col,dx,dy;
        begin
            @(negedge clk);
            previous_active=active; previous_rgb=rgb;
            pixel_x=px; pixel_y=py;
            #1;
            // Nothing changes before the edge: row ROM and validity both delay.
            ck(active===previous_active && rgb===previous_rgb,"OSD output held before pixel clock");
            want_active=(px>=32 && px<1248 && ((py>=8 && py<112)||(py>=608 && py<712)));
            want_rgb=want_active ? 24'h18242C : 24'd0;
            if(px>=48 && px<1232 && ((py>=12 && py<108)||(py>=612 && py<708))) begin
                dy=py<108 ? py-12 : py-612;
                line_no=dy/32 + (py<108 ? 0 : 3);
                col=(px-48)/32; dx=(px-48)%32;
                full_bitmap=items14_ref_bitmap(expected[line_no][col]);
                ink_pixel=full_bitmap[255-((dy%32)/2)*16-(dx/2)];
                case(expected_tone[line_no])
                    1: ink=24'hABE8F2;
                    2: ink=24'hFFE3A3;
                    3: ink=24'h9EF0CC;
                    default: ink=24'hF5F7FA;
                endcase
                if(ink_pixel) want_rgb=ink;
            end
            @(posedge clk); #1;
            ck(active===want_active,"OSD panel boundary and one-clock active");
            ck(rgb===want_rgb,"full bitmap pixel, scale, color, row and one-clock alignment");
        end
    endtask
    task automatic scan_text_span(input integer line_no,input integer first,input integer count);
        integer px,py,start_y;
        begin
            start_y=line_no<3 ? 12+32*line_no : 612+32*(line_no-3);
            for(py=start_y;py<start_y+32;py=py+1)
                for(px=48+32*first;px<48+32*(first+count);px=px+1) sample_pixel(px,py);
        end
    endtask

    initial begin
        ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        start_case("asynchronous reset gates an uninitialized ROM output");
        pixel_x=100; pixel_y=50;
        repeat(2) @(posedge clk);
        #1; ck(active===0 && rgb===0,"reset blacks active and RGB");
        @(negedge clk); rst_n=1;

        start_case("all 4096 ROM words, unassigned glyphs, one-clock data hold");
        for(g=0;g<256;g=g+1) begin
            bitmap=items14_ref_bitmap(g);
            for(row=0;row<16;row=row+1) begin
                @(negedge clk); old_bits=rom_bits; rom_glyph=g; rom_row=row;
                expected_bits=(bitmap >> ((15-row)*16));
                #1; ck(rom_bits===old_bits,"ROM has no combinational response");
                @(posedge clk); #1; ck(rom_bits===expected_bits,"ROM row versus independent whole bitmap");
            end
        end

        mode=1; phase=1;
        for(i=0;i<16;i=i+1) begin
            start_case($sformatf("all item IDs including unknown 0 and 15: %0d",i));
            display_item=i; explore_expected(i); check_content;
            // Include every pixel of the maximum five-character name and one
            // blank cell after it: no leftover glyph when name lengths shrink.
            scan_text_span(5,5,6);
        end
        start_case("question target differs from detected object");
        mode=2; target_item=14; display_item=10; phase=1;
        quiz_expected(14,10); check_content;
        scan_text_span(3,0,10); scan_text_span(5,0,11);
        // All targets must be supported as questions, independently of detection.
        for(i=0;i<16;i=i+1) begin
            start_case($sformatf("question target ID %0d, detected apple stays separate",i));
            target_item=i; quiz_expected(i,10); check_content;
        end

        start_case("unhealthy state supersedes stale detection and answer reveal");
        target_item=14; feedback=3; phase=2; result_healthy=0;
        quiz_expected(14,10);
        clear_line(4); text_at(4,0,42); expected_tone[4]=2;
        clear_line(5); text_at(5,0,43); expected_tone[5]=2;
        check_content; scan_text_span(4,0,21); scan_text_span(5,0,12);

        start_case("healthy reveal identifies the answer rather than claiming detection");
        result_healthy=1;
        clear_line(4); text_at(4,0,21); expected_tone[4]=2;
        clear_line(5); text_at(5,0,26); object_at(5,5,14); expected_tone[5]=2;
        check_content; scan_text_span(5,0,11);

        start_case("success feedback uses object wording");
        feedback=1;
        clear_line(4); text_at(4,0,19); expected_tone[4]=3;
        clear_line(5); text_at(5,0,25); object_at(5,5,10);
        check_content;
        start_case("wrong answer and unarmed removal prompt");
        feedback=2;
        clear_line(4); text_at(4,0,20); expected_tone[4]=2; check_content;
        phase=1; armed=0; clear_line(4); text_at(4,0,23); check_content;

        start_case("test source remains visibly labeled and never appears camera live");
        source_test=1;
        clear_line(1); text_at(1,0,7); expected_tone[1]=2;
        clear_line(4); text_at(4,0,17); expected_tone[4]=2;
        check_content; scan_text_span(1,0,20);
        start_case("test source plus unhealthy retains both warnings");
        result_healthy=0;
        clear_line(4); text_at(4,0,42); expected_tone[4]=2;
        clear_line(5); text_at(5,0,43); expected_tone[5]=2; check_content;

        start_case("ten questions and ten maximum points with finished screen");
        source_test=0; result_healthy=1; phase=3; score=10; question_index=10;
        quiz_expected(14,10);
        expected[0][9]=49; expected[0][10]=48;
        expected[0][20]=49; expected[0][21]=48;
        clear_line(3); text_at(3,0,15); expected[3][14]=49; expected[3][15]=48; expected_tone[3]=3;
        clear_line(4); text_at(4,0,18); expected_tone[4]=3; check_content;
        scan_text_span(0,0,26); scan_text_span(3,0,17);

        start_case("audio fault takes precedence over busy");
        audio_busy=1; clear_line(2); text_at(2,0,10); check_content;
        audio_fault=1; clear_line(2); text_at(2,0,11); expected_tone[2]=2; check_content;

        start_case("standby and invalid mode are explicit");
        mode=0; score=2; question_index=3; phase=1; audio_fault=0; audio_busy=0;
        explore_expected(10);
        for(j=0;j<4;j=j+1) expected[0][j]=items14_ref_text(1,j);
        clear_line(3); text_at(3,0,12); check_content;
        mode=3;
        for(j=0;j<4;j=j+1) expected[0][j]=items14_ref_text(4,j);
        clear_line(3); text_at(3,0,16);
        clear_line(4); text_at(4,0,16); expected_tone[4]=2; check_content;

        start_case("all panel edges and text margins across the full width");
        mode=1; explore_expected(10);
        for(k=0;k<18;k=k+1) begin
            case(k)
                0:y=0;1:y=7;2:y=8;3:y=11;4:y=12;5:y=107;6:y=108;7:y=111;8:y=112;
                9:y=607;10:y=608;11:y=611;12:y=612;13:y=707;14:y=708;15:y=711;16:y=712;default:y=719;
            endcase
            for(x=0;x<1280;x=x+1) sample_pixel(x,y);
        end
        start_case("central ROI never receives a panel or glyph");
        for(y=120;y<600;y=y+1)
            for(x=320;x<960;x=x+31) sample_pixel(x,y);
        for(y=0;y<720;y=y+1) begin
            sample_pixel(31,y); sample_pixel(32,y);
            sample_pixel(1247,y); sample_pixel(1248,y);
        end

        start_case("reset immediately withdraws active panel and flushes sidebands");
        sample_pixel(32,8);
        #1; rst_n=0; #1; ck(active===0 && rgb===0,"asynchronous reset inside a panel");
        @(negedge clk); pixel_x=50; pixel_y=680;
        @(posedge clk); #1; ck(active===0 && rgb===0,"reset remains black despite ROM reads");
        @(negedge clk); rst_n=1; pixel_x=0; pixel_y=0;
        @(posedge clk); #1; ck(active===0 && rgb===0,"reset release does not leak previous panel");
        sample_pixel(208,676); sample_pixel(0,0); sample_pixel(1247,711);

        if(inject_fault) begin
            start_case("negative probe forces exactly one actual glyph output");
            line_index=5; char_index=5; #1;
            force content_dut.glyph=8'hFF;
            #1; injected=injected+1;
            ck(glyph===expected[5][5],"deliberate real glyph corruption must be detected");
            release content_dut.glyph;
            char_index=6; #1;
            ck(glyph===expected[5][6],"negative probe released");
        end
        ck(!inject_fault || injected==1,"exactly one injection when requested");
        test_done=1;
        $display("RESULT tb_items14_display errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);
        $finish;
    end
    initial begin
        #20000000;
        errors=errors+1;
        $display("WATCHDOG tb_items14_display errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);
        $finish;
    end
endmodule
