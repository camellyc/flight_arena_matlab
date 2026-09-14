# run_session_unified.m: dependencies, environment and hardware

Reference for the flight-arena acquisition script in D:\Yichen\Code. Everything in this document was read from the rig PC (DESKTOP-D733TGI) on 2026-09-10 using MATLAB's dependency analyser, the installed-software registry and the device list, except the items in the 'Hardware, guessed' section, which are marked as such.

## 1. What the script needs at a glance

| Layer | Requirement | Version on the rig | Why the script needs it |
|---|---|---|---|
| MATLAB | MATLAB (64-bit Windows) | R2019a Update 9 (9.6.0.1472908) | Runs the script; nested functions, sgtitle, movmax, datetime, VideoWriter |
| MATLAB | Data Acquisition Toolbox | 4.0 (R2019a) | NI session: analog in/out, counter output, queued output, DataAvailable events |
| MATLAB | Image Acquisition Toolbox | 6.0 (R2019a) | Basler cameras via the GenTL adaptor: videoinput, hardware trigger, getdata |
| MATLAB | IMAQ Support Package for GenICam Interface (gentl) | 19.1.0 | Provides the gentl adaptor (mwgentlimaq.dll) used for both Basler cameras |
| MATLAB | MinGW-w64 C/C++ Compiler support package | 19.1.0 (MinGW64 6.3.0, selected) | loadlibrary parses the Phantom C headers (PhConML.h, PhIntML.h, PhFileML.h) at load time |
| Driver | NI-DAQmx | 25.5.0 (reported by daq.getVendors; NI MAX 25.5, NI Package Manager 26.5) | PCIe-6321 driver; vendor 'ni' reports operational |
| Driver | Basler pylon Software Suite | 26.07.2 (runtime PylonBase_v12 12.2.1.1300; USB driver plnu3v 11.3.0) | GenTL producer ProducerU3V.cti for the USB3 cameras; GENICAM_GENTL64_PATH points at C:\Program Files\Basler\pylon\Runtime\x64\ |
| Driver | Phantom Camera Control (PCC) + Phantom SDK | PCC 3.11.11.806; SDK 13.11.11.806 (PhCon.dll / PhFile.dll / PhInt.dll 3.11.11.806) | Camera discovery, cine parameters, capture, store and TIFF/cine save; PCC owns sync mode in framesync mode |
| Rig code | Reiser panels controller code (Panel_com and helpers) | C:\MatlabRoot\FlightArena_setup\panelcode\controller | Arena commands over a serial port (COM5, 921600 baud) |
| Rig code | data_rows.m, exclude_window_stims.m | D:\Yichen\Code | Used by the analysis scripts, not by the acquisition script itself |
| OS | Windows 10 Pro | 10.0.19045 (64-bit) | MPEG-4 VideoWriter profile uses Windows Media Foundation; .NET Framework 4.8 present |

## 2. Files the script calls, and where they live

Output of matlab.codetools.requiredFilesAndProducts('run_session_unified.m'), grouped. The analyser follows every call it can resolve on the saved MATLAB path (pathdef.m in the R2019a install), which contains 28 FlightArena_setup entries and 72 Phantom SDK entries. D:\Yichen\Code itself is not on the saved path; the script is run from that folder as the current directory.

## 2.1 Arena controller (C:\MatlabRoot\FlightArena_setup\panelcode\controller)

| File | Role |
|---|---|
| Panel_com.m | Command encoder: start, stop, set_pattern_id, set_mode, set_position, set_velfunc_id, set_funcy_freq, send_gain_bias. The script calls it through its arenaCmd wrapper. |
| send_serial.m | Writes the command bytes to the global serial port; calls init_serial if the port is not open. |
| init_serial.m | Opens COM5 (default, hard-coded) at 921600 baud, 8N1, LF terminator, using the MATLAB serial interface. |
| dec2char.m, signed_16Bit_to_char.m | Byte packing for multi-byte arguments. |
| displayOnGui.m, update_display_xy.m, update_status_display.m, initialized_PControl_display.m | Serial-port callbacks inherited from the PControl GUI; harmless without the GUI. |
| ..\Pcontrol_paths.mat | Path configuration loaded by the PControl code. |

Note: the MATLAB serial interface (serial, instrfind, fopen) used by init_serial.m was removed in R2022a. This is the main obstacle to running the arena code on a newer MATLAB.

## 2.2 Phantom SDK (D:\Yichen\Code\SDK 13.11.11.806)

| Location | Files used | Role |
|---|---|---|
| matlab\Other | LoadPhantomLibraries.m, UnloadPhantomLibraries.m, RegisterPhantom.m | loadlibrary of phcon.dll, phint.dll and phfile.dll with the *ML.h headers; needs the MinGW compiler |
| matlab\Ph\PhCon | PhSetPartitions, PhGetCineParams, PhSetSingleCineParams, PhRecordCine, PhGetCineStatus, PhLVRegisterClientEx, PhConfigPoolUpdate and siblings | Thin wrappers around the PhCon C API |
| matlab\Ph\PhFile | PhNewCineFromCamera, PhSetUseCase, PhSetCineInfo, PhWriteCineFile, PhDestroyCine and siblings | Saving the stored cine as TIFF12 sequence or .cine |
| matlab\Constants | PhConConst.m, PhFileConst.m, PhIntConst.m | Constants such as SIFILE_TIF12, MIFILE_RAWCINE, UC_SAVE |
| Demo\matlab\PhDemoMatlab\OOP | PoolBuilder.m, PoolRefresher.m, Camera.m, CameraStatus.m, Cine.m, ISource.m | MATLAB classes (not .NET) that wrap camera discovery; the script's camera object is the demo's Camera class, providing Record, RecordSpecificCine, GetCinePartitionStatus, SetSelectedCinePartNo, ToString |
| bin\Win64 | PhCon.Dll, PhFile.Dll, PhInt.Dll, PhSig.dll, PhSigV.dll, PhRange.dll, PhExtLib.dll | Native libraries loaded at run time (version 3.11.11.806) |
| matlab\Ph\Headers_Matlab | PhConML.h, PhFileML.h, PhIntML.h | Headers parsed by loadlibrary; define ACQUIPARAMS (Exposure, dFrameRate, PTFrames, SyncImaging) |

The camera objects come from the SDK's demo folder, so that folder must stay on the path even though it is 'demo' code. PhSetSingleCineParams takes two arguments (camera number, params struct).

## 2.3 MathWorks functions worth knowing about

| Function | Product | Introduced | Notes |
|---|---|---|---|
| daq.createSession, addAnalogInputChannel, addAnalogOutputChannel, addCounterOutputChannel, queueOutputData, startBackground, RateLimit | Data Acquisition Toolbox | session interface, R2013 era | Legacy session interface. With analog outputs present, NotifyWhenDataAvailableExceeds can only be set after queueOutputData. The rate must be set after all channels are added or the board coerces it silently. |
| imaqreset, imaqhwinfo, videoinput, triggerconfig, getselectedsource, getdata, closepreview | Image Acquisition Toolbox + gentl adaptor |  | Cameras selected by serial number in the device name; hardware trigger on Line4; TriggerMode set last. |
| VideoWriter with 'MPEG-4' profile | MATLAB | R2010b | Profile available on this PC: Archival, Grayscale AVI, Indexed AVI, Motion JPEG 2000, Motion JPEG AVI, MPEG-4, Uncompressed AVI |
| sgtitle | MATLAB | R2018b | Sets the minimum release for the script |
| movmax | MATLAB | R2016a | Basler recording band in the live plot |
| datetime, datestr, strjoin, contains, onCleanup, linkaxes, patch, legend, sound, whos -file, matlab.lang.makeValidName | MATLAB | R2016b or earlier |  |
| serial, instrfind, fopen (inside init_serial.m) | MATLAB | removed R2022a | Arena code only |

Minimum MATLAB release implied by the code: R2018b. Maximum: R2021b, because of the serial interface in the arena code. The rig runs R2019a and the code is written and tested against it.

## 3. MATLAB environment on the rig

| Item | Value |
|---|---|
| MATLAB | 9.6.0.1472908 (R2019a) Update 9, PCWIN64 |
| Installed toolboxes | Data Acquisition 4.0, Image Acquisition 6.0, Image Processing 10.4, Signal Processing 8.2, Statistics and Machine Learning 11.5, Curve Fitting 3.5.9, Control System 10.6, Parallel Computing 7.0, Bioinformatics 4.12, Simulink 9.3 |
| Support packages | IMAQ: GenICam Interface 19.1.0, GigE Vision 19.1.0, Hamamatsu 19.1.0; MATLAB Support for MinGW-w64 19.1.0 |
| C compiler | MinGW64 6.3.0, selected (C:\ProgramData\MATLAB\SupportPackages\R2019a\3P.instrset\mingw_w64.instrset) |
| IMAQ adaptors | gentl (mwgentlimaq.dll 6.0), gige, hamamatsu |
| DAQ vendor | ni, National Instruments, driver 25.5.0 NI-DAQmx, operational; device Dev1 = PCIe-6321 |
| Also installed | MATLAB R2022a, R2024a, R2026a (not used by the rig code) |

## 4. Vendor software on the rig

| Package | Version | Purpose |
|---|---|---|
| NI-DAQmx | 25.5.0 (build 25.50.49447), with NI MAX 25.5 and NI Package Manager 26.5 | PCIe-6321 driver and configuration |
| NI Matlab Interface | 25.30.49361 | NI-provided MATLAB integration (installed; the script uses the MathWorks session interface) |
| Basler pylon Software Suite | 26.07.2.18500 (Pylon Viewer, runtime, USB driver plnu3v 11.3.0 dated 2019-07-19) | USB3 Vision driver and GenTL producer for the acA cameras; Pylon Viewer must be closed while MATLAB uses the cameras |
| Phantom Camera Control (PCC) | 3.11.11.806 | Camera setup (sync mode, pre-trigger, ROI, pin functions); the script only sets exposure in framesync mode |
| Phantom SDK | 13.11.11.806 (DLLs 3.11.11.806), vendored in the repo | MATLAB wrappers and native libraries |
| Microsoft .NET Framework | 4.8 | Present; the MATLAB Phantom path uses the C DLLs, not PhSharp.dll |
| Windows | 10 Pro 10.0.19045 |  |

## 5. Hardware, verified from the PC

| Component | Detail | How the script uses it |
|---|---|---|
| PC | Intel Core i7-9800X (8 cores / 16 threads), 63.7 GB RAM, NVIDIA GeForce 8400GS (display only) | In-memory Basler frame buffers for a full block need several GB per camera |
| Storage | C: Samsung 970 EVO 500 GB (system, MATLAB); D: WD 240 GB SSD (code); K: Samsung 990 PRO 1 TB 'flightArena' (Phantom TIFF sequences); H:, J: Google Drive streams (data folder for .mat and Basler MP4); E:, F: 3 TB WD; L: 7.4 TB Seagate | Phantom output goes to K: by design; data folder is on H: (Google Drive) |
| DAQ | NI PCIe-6321, single 68-pin connector, 16 AI (250 kS/s aggregate), 2 AO, 24 DIO, 4 counters; SCB-68A terminal block on an SHC68-68-EPM cable | 13 AI channels single-ended at 10 kHz; AO0 LED, AO1 Phantom trigger; ctr0 on PFI12 Basler trigger |
| Basler top camera | acA1300-200um, serial 22703705, USB3, 2x2 binning, video rotated 90 deg clockwise | Line4 trigger in from PFI12 |
| Basler side camera | acA800-510um, serial 22843477, USB3, video rotated 180 deg | Line4 trigger in; Line3 ExposureActive out to AI11 |
| Phantom camera | Vision Research Phantom KT810, serial 34437, GigE on a dedicated NIC ('Phantom camera adapter', Intel I211) | AO1 to pin 1 Trigger; pin 2 TC in = Frame Sync In; pin 4 FSync P = Recording out to AI14 |
| Network | Intel I219-V (1 Gbps, lab network); Intel I211 (Phantom, direct link) |  |
| Serial | Arena controller expected on COM5 at 921600 baud (init_serial.m). At the time of this inventory only COM3 (FireBird serial port) was enumerated, so the controller's USB-serial adapter was not connected | Panel_com |

## 6. Hardware, guessed (not visible from software; confirm on the bench)

| Component | Best guess | Basis |
|---|---|---|
| LED display arena and controller | Reiser/IORodeo modular LED panel arena (48-column, 8 rows: patterns are 96 x 8 frames) with the Panels controller v3 (XMega) driven by PControl | Panel_com command set, SD-card pattern dimensions, PControl code in the panelcode folder |
| Wingbeat analyzer | JFI Electronics (University of Chicago) wingbeat analyzer, or a lab-built equivalent, outputting WBF (about 2.2 V at rest), WBA left/right and L-R for closed loop | Signal names and voltage ranges in the scripts and data; standard in Dickinson-style tethered-flight rigs |
| Hutchen left/right | A second pair of wing-signal channels, about 4 ms events with 1 ms spikes, from the analyzer or an add-on detector board | Your description; the source is not identifiable from software |
| LED driver | Analog-controlled constant-current driver (0 to 10 V command, for example Thorlabs LEDD1B/DC2200 or Mightex), driving a 617 nm (Chrimson) or 470 nm (CsChrimson/ChR) LED | 10 V command, 200 Hz pulse trains, genotype names in the file names |
| EMG amplifier | Differential extracellular amplifier such as A-M Systems 1700/3000 or a Brownlee/npi unit; output about +/-0.2 V here | EMG channel range in the test data; low-pass should be at or below 4 kHz for 10 kHz sampling |
| Frame-sync generator | Bench function generator producing a 5 V TTL square wave at the Phantom frame rate (1500 Hz in framesync mode) | It is tee'd into AI10 and into the Phantom TC-in configured as Frame Sync In |
| Optics | Not determinable from software |  |

## 7. Files produced by a run

| File | Content |
|---|---|
| <base>.mat in the data folder | Data (14 x N: time plus 13 analog channels), variables, allRandomizedStimOrders, stimTable, params (all settings, channel names, block boundaries, versions), phantom (timing and gate results), baslerInfo (frame counts, timestamps, source-property snapshot) |
| <base>_plot.svg / .png | Summary figure |
| <base>_TopCamera.mp4, <base>_SideCamera.mp4 | MPEG-4, 100 fps, rotated as configured |
| K:\Yichen\spiracle_movies\<experiment>\<base>_PhantomCamera\ | TIFF12 sequence (or .cine) of the Phantom clip |

## 8. Rebuild checklist for a new PC

- Install MATLAB R2019a (R2018b to R2021b will also work) with Data Acquisition Toolbox and Image Acquisition Toolbox.
- Add-Ons: Image Acquisition Toolbox Support Package for GenICam Interface; MATLAB Support for MinGW-w64 C/C++ Compiler (then run mex -setup C).
- Install NI-DAQmx 25.5 (or any release supporting the PCIe-6321) and confirm Dev1 in NI MAX.
- Install Basler pylon Software Suite; confirm GENICAM_GENTL64_PATH points at the pylon Runtime\x64 folder and that both cameras appear in imaqhwinfo('gentl').
- Install Phantom PCC 3.11.11.806 and add the repo's SDK 13.11.11.806 folders (matlab\*, Demo\matlab\PhDemoMatlab\OOP, bin\Win64) to the MATLAB path; confirm LoadPhantomLibraries runs without error.
- Copy C:\MatlabRoot\FlightArena_setup\panelcode to the same location or add it to the path; set the controller COM port in init_serial.m.
- Verify with hw.simulate = true first (no hardware needed), then a short real block.
