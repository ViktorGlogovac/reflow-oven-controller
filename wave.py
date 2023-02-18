import time 
import serial 
    
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys
 
ser = serial.Serial( 
    port='COM3', 
    baudrate=115200, 
    parity=serial.PARITY_NONE, 
    stopbits=serial.STOPBITS_TWO, 
    bytesize=serial.EIGHTBITS 
) 
ser.isOpen() 


xsize=100
   
def data_gen():
    t = data_gen.t
    while True:
       t=t+1
       string = ser.readline()
       values = int(string)
       val=values
       
       yield t, val

def run(data):

    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
    if y > 30:
        color = 'red'
        plt.text(t, y, 'Too Hot', fontweight='bold', color=color)
    else:
        color = 'blue'
    line.set_data(xdata, ydata)
    line.set_color(color)
    if t>xsize: 
        ax.set_xlim(t-xsize, t)

    return line,



def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
ax.set_xlabel('Time (t)')
ax.set_ylabel('temperature (y)')
line, = ax.plot([], [], lw=2)
ax.set_ylim(0, 250)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
