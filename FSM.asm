

DSEG ; Before the state machine!
state: ds 1
temp_soak: ds 1
Time_soak: ds 1
Temp_refl: ds 1
Time_refl: ds 1


FSM1:
mov a, FSM1_state

FSM1_state0:
cjne a, #0, FSM1_state1
mov pwm, #0
jb PB6, FSM1_state0_done
jnb PB6, $ ; Wait for key release
mov FSM1_state, #1

FSM1_state0_done:
ljmp FSM2

FSM1_state1:
cjne a, #1, FSM2_state2
mov pwm, #100
mov sec, #0
mov a, temp_soak
clr c
subb a, temp
jnc FSM1_state1_done
mov FSM1_state, #2

FSM1_state1_done:
ljmp FSM2

FSM1_state2:
cjne a, #2, FSM1_state3
mov pwm, #20
mov a, time_soak
clr c
subb a, sec
jnc FSM1_state2_done
mov FSM1_state, #3

FSM1_state2_done:
ljmp FSM2

FSM1_state3:
cjne a, #3, FSM1_state4
mov pwm, #100
mov a, #220, reflow_temp
clr c
subb a, oven_temp
jnc FSM1_state3_done
mov FSM1_state, #3

FSM1_state3_done:
ljmp FSM2

FSM1_state4: 
cjne a, #4, FSM1_state5
mov pwm, #20
mov a, Time_refl
clr c,
subb a , Time_soak
jnc FSM1_state4_done
mov FSM1_state, #5

FSM1_state4_done:
ljmp FSM2

FSM1_state5:
cjne a, #5,  
mov pwm, #0
mov a, #60
clr c
subb a, reflow temp
jnc FSM_state5_done
mov state, #0

FSM1_state5_done:
ljmp FSM2









