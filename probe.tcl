# Xcelium probe script: dump everything to an SHM database for SimVision
database -open waves -into waves.shm -default
probe -create tb_top -all -depth all -database waves
run
exit
