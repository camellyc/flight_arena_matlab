figure; 

for ii =1:10
    
    plot(Data(ii,:))
    pause
end 


fs = 10000;
camrate = 10;
cameratrig = zeros(1,10*fs);
cameratrig(1:fs/camrate:end) = 5;



