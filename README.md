# binw2
Binary Wrist Watch with ATtiny13

# Debugging
simulavr -g -d attiny45
avr-gdb
(gdb) target remote localhost:1212
(gdb) file /Users/fvicente/workspace/alfersoft.com.ar-repos/binw2/src/binw2.o
(gdb) load
(gdb) step


# Preparing pysimulavr
brew install swig
cd simulavr/src/python
sudo python2.6 setup.py install
