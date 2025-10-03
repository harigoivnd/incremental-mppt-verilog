`timescale 1ns/1ps
`include "mainmod.v"

module tb_inc_cond_mppt;

    // Testbench signals
    reg clk, reset, start;
    reg [15:0] voltage_in, current_in;
    wire [15:0] duty_cycle, power_out;
    wire mpp_found;
    
    // Clock generation
    always #5 clk = ~clk; // 100MHz clock
    
    // Instantiate DUT - Make sure this matches your actual module name
    // If your module is called "inc_cond_mppt", keep this
    // If it's called something else, change it here
    inc_cond_mppt dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .voltage_in(voltage_in),
        .current_in(current_in),
        .duty_cycle(duty_cycle),
        .mpp_found(mpp_found),
        .power_out(power_out)
    );
    
    // Solar panel characteristic simulation
    reg [15:0] irradiance;
    reg [15:0] temperature;
    reg [15:0] simulated_current;
    
    // Power Monitoring Variables
    real total_power;
    integer sample_count;
    integer cycle_count;
    real average_power;
    real max_power;
    real min_power;
    
    // Environmental condition tracking
    reg [7:0] condition_id;
    reg [127:0] condition_name; // Changed from string to reg for iverilog compatibility
    
    // Task to simulate solar panel
    task simulate_solar_panel;
        input [15:0] v_sim;
        output [15:0] i_sim;
        reg [31:0] i_calc;
        begin
            // Simplified solar panel I-V characteristic
            if (v_sim < 16'h2000) begin // Below 32V
                i_calc = 16'h0C00 - ((v_sim * 16'h0040) >> 8); // Linear region
            end else begin
                // Quadratic drop near Voc
                i_calc = 16'h0800 - (((v_sim - 16'h2000) * (v_sim - 16'h2000)) >> 10);
            end
            
            // Apply irradiance and temperature effects
            i_calc = (i_calc * irradiance) >> 12;
            
            // Temperature effect (simplified)
            if (temperature > 16'h0C80) begin // Above 25°C
                i_calc = i_calc - ((temperature - 16'h0C80) >> 4);
            end
            
            i_sim = (i_calc > 0) ? i_calc[15:0] : 16'h0000;
        end
    endtask
    
    // Function to convert fixed-point to real
    function real fixed_to_real;
        input [15:0] fixed_value;
        real result;
        begin
            result = fixed_value;
            result = result / 256.0; // Q8.8 to real
            fixed_to_real = result;
        end
    endfunction
    
    // Power monitoring task
    task monitor_power;
        input [127:0] condition;
        input integer duration_cycles;
        real current_power_real;
        real power_ripple;
        real tracking_efficiency;
        real theoretical_max;
        begin
            $display("\n=== Starting Power Monitoring: %s ===", condition);
            $display("Time: %0t ns", $time);
            
            // Reset power statistics for this condition
            total_power = 0.0;
            sample_count = 0;
            max_power = 0.0;
            min_power = 999999.0;
            
            // Monitor for specified duration
            repeat (duration_cycles) begin
                @(posedge clk);
                #1; // Wait a bit after clock edge
                
                if (!reset) begin
                    // Update power statistics
                    current_power_real = fixed_to_real(power_out);
                    
                    total_power = total_power + current_power_real;
                    sample_count = sample_count + 1;
                    
                    if (current_power_real > max_power) 
                        max_power = current_power_real;
                    if (current_power_real < min_power && current_power_real > 0) 
                        min_power = current_power_real;
                end
            end
            
            // Calculate and display results
            if (sample_count > 0) begin
                average_power = total_power / sample_count;
                power_ripple = max_power - min_power;
                theoretical_max = fixed_to_real(16'h0C00) * fixed_to_real(16'h2000) * fixed_to_real(irradiance);
                tracking_efficiency = (average_power / theoretical_max) * 100.0;
                
                $display("=== Power Statistics: %s ===", condition);
                $display("Monitoring Duration: %0d cycles", duration_cycles);
                $display("Samples Collected: %0d", sample_count);
                $display("Average Power: %.2f W", average_power);
                $display("Maximum Power: %.2f W", max_power);
                $display("Minimum Power: %.2f W", min_power);
                $display("Power Ripple: %.2f W (%.1f%%)", 
                         power_ripple, 
                         (power_ripple / average_power) * 100.0);
                $display("Theoretical Max Power: %.2f W", theoretical_max);
                $display("Tracking Efficiency: %.1f%%", tracking_efficiency);
                $display("=================================\n");
            end
        end
    endtask
    
    // Change environmental condition
    task change_condition;
        input [15:0] new_irradiance;
        input [15:0] new_temperature;
        input [7:0] new_condition_id;
        input [127:0] new_condition_name;
        begin
            $display("\n*** Changing Condition to: %s ***", new_condition_name);
            $display("Old Irradiance: %h (%.2f sun)", irradiance, fixed_to_real(irradiance));
            $display("New Irradiance: %h (%.2f sun)", new_irradiance, fixed_to_real(new_irradiance));
            $display("Old Temperature: %h (%.1f °C)", temperature, fixed_to_real(temperature));
            $display("New Temperature: %h (%.1f °C)", new_temperature, fixed_to_real(new_temperature));
            
            irradiance = new_irradiance;
            temperature = new_temperature;
            condition_id = new_condition_id;
            condition_name = new_condition_name;
            
            // Allow some time for transition
            #1000;
        end
    endtask
    
    // Main test sequence
    integer i;
    reg [15:0] simulated_voltage;
    
    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        start = 0;
        voltage_in = 16'h0000;
        current_in = 16'h0000;
        irradiance = 16'h1000; // 1.0 sun
        temperature = 16'h0C80; // 25°C
        condition_id = 0;
        condition_name = "Initial";
        
        // Initialize power monitoring
        total_power = 0.0;
        sample_count = 0;
        average_power = 0.0;
        max_power = 0.0;
        min_power = 999999.0;
        cycle_count = 0;
        
        // Reset sequence
        #100;
        reset = 0;
        #10;
        start = 1;
        
        $display("========== MPPT SIMULATION STARTED ==========");
        $display("Initial Conditions: 1.0 sun, 25°C");
        $display("============================================\n");
        
        // Test Case 1: Standard Conditions (1.0 sun, 25°C)
        change_condition(16'h1000, 16'h0C80, 1, "Standard Conditions");
        monitor_power("Standard Conditions (1.0 sun, 25°C)", 500);
        
        // Test Case 2: Reduced Irradiance (0.7 sun)
        change_condition(16'h0B00, 16'h0C80, 2, "Reduced Irradiance");
        monitor_power("Reduced Irradiance (0.7 sun, 25°C)", 500);
        
        // Test Case 3: Partial Shading (0.4 sun)
        change_condition(16'h0660, 16'h0C80, 3, "Partial Shading");
        monitor_power("Partial Shading (0.4 sun, 25°C)", 500);
        
        // Test Case 4: High Temperature (45°C)
        change_condition(16'h1000, 16'h1680, 4, "High Temperature");
        monitor_power("High Temperature (1.0 sun, 45°C)", 500);
        
        // Test Case 5: Low Irradiance + High Temperature
        change_condition(16'h0800, 16'h1680, 5, "Cloudy & Hot");
        monitor_power("Cloudy & Hot (0.5 sun, 45°C)", 500);
        
        // Test Case 6: Return to Standard
        change_condition(16'h1000, 16'h0C80, 6, "Return to Standard");
        monitor_power("Return to Standard Conditions", 500);
        
        // Final Summary
        $display("\n========== SIMULATION COMPLETED ==========");
        $display("Total Simulation Time: %0t ns", $time);
        $display("Total Clock Cycles: %0d", cycle_count);
        $display("==========================================\n");
        
        $finish;
    end
    
    // Cycle counter
    always @(posedge clk) begin
        if (reset) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end
    
    // Main simulation loop
    always @(posedge clk) begin
        if (!reset && start) begin
            // Simulate solar panel response based on duty cycle
            simulated_voltage = (duty_cycle * 16'h0040) >> 8;
            simulate_solar_panel(simulated_voltage, simulated_current);
            
            voltage_in = simulated_voltage;
            current_in = simulated_current;
            
            // Display occasional status
            if (cycle_count % 200 == 0) begin
                $display("Cycle: %4d | Condition: %s | Duty: %4h (%.1f%%) | V: %.1fV | I: %.1fA | P: %.1fW | MPP: %b",
                        cycle_count, condition_name, duty_cycle, 
                        (fixed_to_real(duty_cycle) / 256.0) * 100.0,
                        fixed_to_real(voltage_in),
                        fixed_to_real(current_in),
                        fixed_to_real(power_out),
                        mpp_found);
            end
        end
    end
    
    // Real-time power display every MPP found
    always @(posedge mpp_found) begin
        if (!reset) begin
            $display("MPP Found! Cycle: %d | Power: %.1fW | Condition: %s", 
                    cycle_count, fixed_to_real(power_out), condition_name);
        end
    end
    
    // File output for waveform analysis
    initial begin
        $dumpfile("inc_cond_mppt.vcd");
        $dumpvars(0, tb_inc_cond_mppt);
    end

endmodule