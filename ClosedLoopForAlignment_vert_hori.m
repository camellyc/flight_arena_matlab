 %% Closed loop for Alignment 
 CLStripe = 13;
 CL_X_gain = -5;     % closed loop gain
 panel_pause = .005; %  short time to 'space out' commands send to controller

Panel_com('stop'); pause(panel_pause); 
Panel_com('set_pattern_id', CLStripe); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause); % the mode code for CL on X
Panel_com('set_position', [72 1]); pause(panel_pause); % randomize at some point?
Panel_com('send_gain_bias',[CL_X_gain,0,0,0]); pause(panel_pause);
Panel_com('start');  