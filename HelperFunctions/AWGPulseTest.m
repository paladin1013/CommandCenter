

val = "18.25.24.255";
format shortg
c = clock;
waveformName1 = sprintf("waveform_ch1_%d_%d", c(4), c(5));
file_path1 = sprintf('\\\\houston.mit.edu\\qpgroup\\Experiments\\AWG70002B\\waveforms\\%s.txt', waveformName1);
waveformName2 = sprintf("waveform_ch2_%d_%d", c(4), c(5));
file_path2 = sprintf('\\\\houston.mit.edu\\qpgroup\\Experiments\\AWG70002B\\waveforms\\%s.txt', waveformName2);
AWG_Amplitude_V = 0.25;
AWG_SampleRate_GHz = 10;

% pulseData1 = genPulse1;
% writematrix(pulseData1, file_path1);
pulseData2 = genPulse2;
writematrix(pulseData2, file_path2);

AWG=Drivers.AWG70002B.instance('visa',val);
AWG_IP = val;
% AWG.reset();
% AWG.setExtRefClock();
% AWG.setSampleRate(1, AWG_SampleRate_GHz*1e9);
% AWG.setSampleRate(2, AWG_SampleRate_GHz*1e9);
% AWG.writeReadToSocket('SYST:ERR:ALL?');
AWG.loadWaveform(1, waveformName2);
% AWG.writeToSocket('RCC 1');
AWG.setAmplitude(1, AWG_Amplitude_V);
% AWG.setResolution(1, 8);
% AWG.setChannelOn(1);
% AWG.setRunMode(1, 'C');
% AWG.setAmplitude(1, AWG_Amplitude_V);

AWG.loadWaveform(2, waveformName2);
AWG.setAmplitude(2, AWG_Amplitude_V);

% AWG.setResolution(2, 8);
% AWG.setChannelOn(2);
% AWG.setRunMode(2, 'C');
AWG.AWGStart;


% function pulseData = genPulse1()
%     nSamples = 5000;
%     pulseData = zeros(nSamples, 3);
%     t = 0:0.1:10;
%     l = length(t);
%     delay = 1;
%     tau = 2;
%     pulseData(1:l) = exp(-t/tau);
%     % pulseData(1:l) = 1;
%     comp1Start = delay*10;
%     pulseData(comp1Start:comp1Start+l-1) = pulseData(comp1Start:comp1Start+l-1) - exp(-(t+delay)/tau);
%     comp2Start = delay*2*10;
%     pulseData = pulseData/3;
% end
function pulseData = genPulse2()
    nSamples = 100000;
    pulseData = zeros(nSamples, 3);
    t = 0:0.1:10;
    l = length(t);
    delay = 1;
    tau = 0.5;
    % pulseData(1:delay/0.1) = 1;
    pulseData(1:l) = exp(-t/tau);
    comp1Start = delay*10;
    pulseData(comp1Start:comp1Start+l-1) = pulseData(comp1Start:comp1Start+l-1) - 0.4*exp(-(t)/5/tau);
    
    % pulseData(comp1Start:comp1Start+l-1) = pulseData(comp1Start:comp1Start+l-1)
    comp2Start = delay*2*10;
    % pulseData(compEnd)
    pulseData = [pulseData]/5*2;
end
