# compile your files
#

# elaborate and load the design
vsim -voptargs=+acc work.axi_top_tb

# load the waveform setup
do wave.do

# run the simulation
#run -all