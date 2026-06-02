import re

def refactor_pea_top():
    with open('rtl/pea_top.sv', 'r') as f:
        content = f.read()

    # Replacements for start/done to ctrl_start/ctrl_done
    content = re.sub(r'\bstart\b', 'ctrl_start', content)
    content = re.sub(r'\bdone\b', 'ctrl_done', content)
    content = re.sub(r'\bdone_comb\b', 'r_done_comb', content)
    content = re.sub(r'\bdone_d1\b', 'r_done_d1', content)

    # Replace variables with r_ (registers/always blocks)
    regs = [
        'reg_ifm_width', 'reg_ifm_height', 'reg_channels_in', 'reg_channels_out', 
        'reg_kernel_size', 'reg_right_shift', 'reg_row_stride', 'reg_col_stride', 
        'reg_weight_base', 'reg_bias_base', 'reg_relu_en', 'reg_pool_en',
        'state', 'next_state', 'loop_cout', 'loop_y', 'loop_cin', 'loop_ky', 'loop_kx',
        'load_counter', 'stream_cnt', 'psum_flush_cnt', 'lb_load_row_cnt', 'lb_load_col_cnt',
        'load_full_lb', 'load_weight_en', 'bias_array', 'lb_we', 'lb_write_row', 'lb_write_col',
        'state_delayed', 'load_counter_delayed', 'data_en_delayed', 'psum_en_top_delayed',
        'swap_weight_delayed', 'psum_bram', 'psum_bram_dout', 'psum_read_addr', 'psum_write_addr',
        'psum_we', 'psum_din', 'psum_out_delayed', 'psum_en_delayed', 'psum_write_addr_reg',
        'is_first_acc_delayed', 'post_proc_en', 'post_proc_x', 'final_ofm', 'ofm_we_reg',
        'post_proc_x_delayed', 'loop_y_delayed', 'loop_cout_delayed'
    ]

    for reg in regs:
        if reg == 'state':
            content = re.sub(r'\bstate\b', 'r_state', content)
        elif reg == 'next_state':
            content = re.sub(r'\bnext_state\b', 'r_next_state', content)
        else:
            content = re.sub(rf'\b{reg}\b', f'r_{reg}', content)

    # Replace variables with w_ (wires/assigns)
    wires = [
        'out_width', 'tiles_per_cout', 'rows_to_load', 'tile_index', 'is_first_acc',
        'swap_weight_in_global', 'data_en_left', 'psum_en_top', 'psum_in_top',
        'psum_out_bottom', 'psum_en_bottom', 'current_load_abs_row', 'lb_read_row',
        'lb_read_col', 'lb_read_data'
    ]
    
    for wire in wires:
        content = re.sub(rf'\b{wire}\b', f'w_{wire}', content)

    with open('rtl/pea_top.sv', 'w') as f:
        f.write(content)

if __name__ == "__main__":
    refactor_pea_top()
