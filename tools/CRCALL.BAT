@ECHO OFF
REM CRCALL.BAT - checksums of all game files into CRC.TXT (run in the game folder)
ECHO [.] > CRC.TXT
CRCLIST >> CRC.TXT
FOR %%D IN (DATA CRIT CUTS SOUND SAVE0) DO CALL CRCDIR.BAT %%D
ECHO Done: CRC.TXT
