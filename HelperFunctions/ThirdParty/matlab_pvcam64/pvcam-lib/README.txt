Originally from matPVCAM source.
deleted pv_icl(not needed for my project), and replaced all 32bit library with 64bit library from Photometrics.
exchange boolean to rs_bool for Visual Studio complier.

Sample Compile code in MATLAB terminal:
mex <directory> pvcam64.lib pvcamopen.c pvcamutil.c

PRIME sCMOS features:
1. No need to change readout rate
2. No need to change gain
3. 180 to 200 DN bias, not recommended to change
4. Clear Pre-Sequence need to be turned on for time-lapse or timed slow acquisition
4. ROI, cannot be smaller than 2000 pixels
5. Trigger: default is internal camera timed mode, others: trigger-first, edge mode
6. Expose Out: First Row overlaps rolling shutter, Any Row from shutter open to close, All Rows only take when shutter is fully open
7. Multiple output triggers, 4 in total
8. SMART streaming allows different trigger with different exposure time
9. Fan speed control, high, medium, low and liquid cooling
10. PrimeEnhance controls: no. of iterations in algo (3), 100*system gain, prime bias offset - 100, on or off but become fixed in the future
11. PrimeLocate, enable and control number of ROIs per frame and size
12. Time Stamps: output "metadata" including exposure ROI and timestamps, inserted in the frame buffer and transfeered, timestamps accuracy 10usec

Post Processing Feautre:
1. Use pvcamppshow to see a comprehensive list of post processing features available to this particular camera, remember the feature, function indices, and possible values.
2. Use pvcamselect to change the value of a chosen feature, function.