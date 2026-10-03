function automatic [1:0] reference_color(input [23:0] rgb);
    integer red_value, green_value, blue_value;
    begin
        red_value = rgb[23:16];
        green_value = rgb[15:8];
        blue_value = rgb[7:0];
        reference_color = 0;
        if (red_value >= 96 && green_value >= 80 && blue_value <= 96 &&
            red_value-green_value <= 80 && green_value-red_value <= 80 &&
            red_value-blue_value >= 32 && green_value-blue_value >= 24)
            reference_color = 2;
        else if (red_value >= 80 && red_value-green_value >= 32 && red_value-blue_value >= 32)
            reference_color = 1;
        else if (blue_value >= 80 && blue_value-red_value >= 24 && blue_value-green_value >= 24)
            reference_color = 3;
    end
endfunction
