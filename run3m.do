# compile your files
vlog rtl/*.sv

# elaborate and load the design
vsim -voptargs=+acc work.axi_top_1m3s_tb

# load the waveform setup
do wave3m.do

# run the simulation
#run -all