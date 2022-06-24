

val = '18.25.28.214';
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


% pulsePeriod_ns, sampleFreq_GHz, pulseAmp, t1, tau1, t2, compRatio, delayTau, prolong_ns
pulseData = genPulse(1000,... % pulsePeriod_ns
     10, ... % sampleFreq_GHz
     1, ... % pulseAmp
     20, ... % t1
     0.3, ... % tau1
     20, ... % t2
     -0.1, ... % compRatio
     0.5, ... % compTau
     0.5); % prolong_ns
    
writematrix(pulseData, file_path2);

AWG = Drivers.AWG70002B.instance('visa', '18.25.28.214');
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

function pulseData = genPulse(pulsePeriod_ns, sampleFreq_GHz, pulseAmp, t1, tau1, t2, compRatio, compTau, prolong_ns)
    % if pulseWidth_ns < 10
    %     nSamples = pulsePeriod_ns*sampleFreq_GHz;
    %     pulseData = zeros(nSamples, 3);
    %     pulseData(1:t2*sampleFreq_GHz) = 1;
    %     decayT = t2:(1/sampleFreq_GHz):pulseWidth_ns;
    %     pulseData(t2*sampleFreq_GHz:pulseWidth_ns*sampleFreq_GHz, 1) = exp(-decayT/tau1);
    %     compT = pulseWidth_ns*sampleFreq_GHz:(1/sampleFreq_GHz):(pulseWidth_ns+prolong_ns)*sampleFreq_GHz;
    %     pulseData(compT*sampleFreq_GHz) = compRatio*exp(-(compT-pulseWidth_ns)/compTau);
    %     pulseData(:, 1) = pulseData(:, 1)*pulseAmp;
    % end
    % else

        nSamples = pulsePeriod_ns*sampleFreq_GHz;
        pulseData = zeros(nSamples, 3);

        t = (1/sampleFreq_GHz):(1/sampleFreq_GHz):t1;

        pulseData(1:t1*sampleFreq_GHz, 1) = exp(-t/tau1)*0.3+0.8;
        pulseData(t1*sampleFreq_GHz: t2*sampleFreq_GHz, 1) = 0.8;
        
        pulseData(t2*sampleFreq_GHz+1:(t2+t1)*sampleFreq_GHz, 1) = -exp(-t/tau1)*0.3-0.8;
        pulseData((t2+t1)*sampleFreq_GHz: 2*t2*sampleFreq_GHz, 1) = -0.8;
        % t1 = 10;
        % risingT = (1/sampleFreq_GHz):(1/sampleFreq_GHz):t1;
        % pulseData(1:t1*sampleFreq_GHz, 1) = 0.5*log((risingT)/t1*(exp(5)-1)+1)/5;
        % pulseData(1:t1*sampleFreq_GHz, 1) = risingT/t1;
%         decayT = t2:(1/sampleFreq_GHz):pulseWidth_ns;
%         pulseData(t2*sampleFreq_GHz:pulseWidth_ns*sampleFreq_GHz, 1) = exp(-decayT/tau1);
%         compT = pulseWidth_ns*sampleFreq_GHz:(1/sampleFreq_GHz):(pulseWidth_ns+prolong_ns)*sampleFreq_GHz;
%         pulseData(compT*sampleFreq_GHz) = compRatio*exp(-(compT-pulseWidth_ns)/compTau);
        % pulseData(t2*sampleFreq_GHz:t2*sampleFreq_GHz*2, 1) = -1;
        pulseData(:, 1) = pulseData(:, 1)*pulseAmp;
    % end
end
