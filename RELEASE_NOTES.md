# Shiori 1.0.1

Fixes to track down the crash during the first scan.

- The log is now written to disk line by line, so its last lines survive a crash.
- If Shiori didn't close properly last time, the next start says so in the log. It also copies in the end of the previous run's log and Windows' own crash record for Shiori.exe.
- The scan writes its progress and memory use to the log file after every 24 files, and a heartbeat line every 30 seconds.
- The scan copies less data to its background workers, and refreshes the library at most every 3 seconds while it runs, so the window stays more responsive on large libraries.
- Sorting by name is faster.
