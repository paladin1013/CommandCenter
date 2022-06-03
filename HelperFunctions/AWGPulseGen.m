function PulseData = AWGPulseGen(Amplitude, PulseWidth_ns, PulsePeriod_ns, MarkerWidth_ns, PulseRepeat, AWG_SampleRate_GHz, file_path)
    NSample = PulsePeriod_ns*PulseRepeat*AWG_SampleRate_GHz;
    PulseData = zeros(NSample, 3);
    PulseData(1:MarkerWidth_ns*AWG_SampleRate_GHz, 2) = 1;
    for cnt = 1:PulseRepeat
        PulseData(1+(cnt-1)*PulsePeriod_ns*AWG_SampleRate_GHz:(PulseWidth_ns+(cnt-1)*PulsePeriod_ns)*AWG_SampleRate_GHz, 1) = Amplitude;
    end
    

    if exist('file_path', 'var')
        % file = fopen(file_path, 'w');
        writematrix(PulseData, file_path);
    end
        
        
end
