module inc_cond_mppt (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [15:0] voltage_in,
    input wire [15:0] current_in,
    output reg [15:0] duty_cycle,
    output reg mpp_found,
    output reg [15:0] power_out
);

    // Parameters
    parameter DUTY_STEP = 16'h0040; // 0.25 in 8.8 format
    parameter DELTA_V = 16'h0008;   // Minimum voltage change
    parameter MAX_DUTY = 16'h3FFF;  // Maximum duty cycle
    parameter MIN_DUTY = 16'h0001;  // Minimum duty cycle
    
    // Internal registers
    reg [15:0] v_prev, i_prev, p_prev;
    reg [15:0] dv, di, conductance, inc_conductance;
    reg [31:0] power_calc;
    reg [1:0] state;
    
    // State definitions
    localparam IDLE = 2'b00;
    localparam CALCULATE = 2'b01;
    localparam UPDATE = 2'b10;
    
    // Power calculation
    always @* begin
        power_calc = voltage_in * current_in; // 32-bit result
        power_out = power_calc[23:8]; // Scale down to 16-bit
    end
    
    // Main algorithm FSM
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            v_prev <= 16'h0000;
            i_prev <= 16'h0000;
            p_prev <= 16'h0000;
            duty_cycle <= 16'h2000; // Start at 50% duty
            mpp_found <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        v_prev <= voltage_in;
                        i_prev <= current_in;
                        p_prev <= power_out;
                        state <= CALCULATE;
                    end
                end
                
                CALCULATE: begin
                    // Calculate differences
                    dv = voltage_in - v_prev;
                    di = current_in - i_prev;
                    
                    // Avoid division by implementing comparison directly
                    if (dv == 0) begin
                        if (di == 0) begin
                            // Operating point unchanged
                            mpp_found <= 1'b1;
                        end else begin
                            // Change duty based on current change
                            if (di > 0) begin
                                duty_cycle <= (duty_cycle < MAX_DUTY) ? 
                                             duty_cycle + DUTY_STEP : MAX_DUTY;
                            end else begin
                                duty_cycle <= (duty_cycle > MIN_DUTY) ? 
                                             duty_cycle - DUTY_STEP : MIN_DUTY;
                            end
                            mpp_found <= 1'b0;
                        end
                    end else begin
                        // Calculate conductances using fixed-point approximation
                        // Simple comparison without division
                        if (di == 0) begin
                            // No current change
                            mpp_found <= 1'b1;
                        end else if ((di > 0 && dv > 0) || (di < 0 && dv < 0)) begin
                            // Left of MPP - increase voltage
                            duty_cycle <= (duty_cycle < MAX_DUTY) ? 
                                         duty_cycle + DUTY_STEP : MAX_DUTY;
                            mpp_found <= 1'b0;
                        end else begin
                            // Right of MPP - decrease voltage
                            duty_cycle <= (duty_cycle > MIN_DUTY) ? 
                                         duty_cycle - DUTY_STEP : MIN_DUTY;
                            mpp_found <= 1'b0;
                        end
                    end
                    
                    state <= UPDATE;
                end
                
                UPDATE: begin
                    // Store current values as previous for next iteration
                    v_prev <= voltage_in;
                    i_prev <= current_in;
                    p_prev <= power_out;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule