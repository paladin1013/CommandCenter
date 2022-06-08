function PulseData = AWGPulseGen(BaseAmplitude, PulseWidth_ns, PulsePeriod_ns, MarkerWidth_ns, PulseRepeat, AWG_SampleRate_GHz, file_path, PulseShape, PulseParams)
    if length(PulseWidth_ns) == 1
        NSamples = PulsePeriod_ns*PulseRepeat*AWG_SampleRate_GHz;
        PulseData = zeros(NSamples, 3);
        PulseData(:, 1) = BaseAmplitude;
        PulseData(1:MarkerWidth_ns*AWG_SampleRate_GHz, 2) = 1;
        for cnt = 1:PulseRepeat
            if PulseWidth_ns == 0
                continue
            end
            NPulseSamples = PulseWidth_ns*AWG_SampleRate_GHz;
            PulseSampleInd = [1:NPulseSamples];
            startIdx = 1+(cnt-1)*PulsePeriod_ns*AWG_SampleRate_GHz;
            endIdx = (PulseWidth_ns+(cnt-1)*PulsePeriod_ns)*AWG_SampleRate_GHz;
            if (exist("PulseParams", "var"))
                PulseData(startIdx:endIdx, 1) = BaseAmplitude+(1-BaseAmplitude)*assignData(PulseSampleInd, PulseShape, PulseParams);
            else
                PulseData(startIdx:endIdx, 1) = BaseAmplitude+(1-BaseAmplitude)*assignData(PulseSampleInd, PulseShape);
            end

        end
    else 
        NPulseWidths = length(PulseWidth_ns);
        NSamples = NPulseWidths*PulsePeriod_ns*AWG_SampleRate_GHz*PulseRepeat;
        PulseData = zeros(NSamples, 3);
        PulseData(1:MarkerWidth_ns*AWG_SampleRate_GHz, 2) = 1;
        for repeatCnt = 1:PulseRepeat
            for pulseWidthCnt = 1:NPulseWidths
                startIdx = ((repeatCnt-1)*NPulseWidths+pulseWidthCnt-1)*PulsePeriod_ns*AWG_SampleRate_GHz + 1;
                endIdx =   (((repeatCnt-1)*NPulseWidths+pulseWidthCnt-1)*PulsePeriod_ns+PulseWidth_ns(pulseWidthCnt))*AWG_SampleRate_GHz;
                if PulseWidth_ns(pulseWidthCnt) == 0
                    continue
                end
                NPulseSamples = PulseWidth_ns(pulseWidthCnt)*AWG_SampleRate_GHz;
                PulseSampleInd = [1:(NPulseSamples)];
                PulseData(startIdx:endIdx, 1) = (1-BaseAmplitude)*assignData(PulseSampleInd, PulseShape, PulseParams);   
                if (exist("PulseParams", "var"))
                    PulseData(startIdx:endIdx, 1) = (1-BaseAmplitude)*assignData(PulseSampleInd, PulseShape, PulseParams);   
                else
                    PulseData(startIdx:endIdx, 1) = (1-BaseAmplitude)*assignData(PulseSampleInd, PulseShape);   
                end
    
            end
        end
    end

    if exist('file_path', 'var')
        % file = fopen(file_path, 'w');
        writematrix(PulseData, file_path);
    end
        
        
end

function data = assignData(PulseSampleInd, PulseShape, PulseParams)
    NPulseSamples = length(PulseSampleInd);
    if (~exist("PulseShape", "var") || PulseShape == "square")
        data = 1;
    elseif PulseShape == "sine"
        data = sin(PulseSampleInd'./NPulseSamples*pi);   
    elseif PulseShape == "Gaussian"
        if exist("PulseParams", "var")
            assert(length(PulseParams) == 2, "There should be two parameters (sigma, mu) for gaussian pulse");
            data = gaussmf(PulseSampleInd', [PulseParams(1), PulseParams(2)]);
        else
            data = gaussmf(PulseSampleInd', [NPulseSamples/8, NPulseSamples/2]);
        end
    elseif PulseShape == "exponential"
        if exist("PulseParams", "var")
            assert(length(PulseParams) == 1, "There should be one parameter (tau) for exponential decay pulse");
            data = exp(-(PulseSampleInd-1)'/PulseParams);
        else
            data = exp(-(PulseSampleInd-1)'/(NPulseSamples/5));
        end
    end


end