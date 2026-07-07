#!/usr/bin/env python3
"""Forces QEMU Cocoa display to update by triggering View→VGA periodically.
Built-in workaround for QEMU-on-macOS VGA framebuffer not updating in real-time.
"""
import subprocess
import time
import sys

APPLESCRIPT = '''
tell application "System Events"
  set qemuList to every process whose name contains "qemu"
  if (count of qemuList) > 0 then
    set qemuProcess to item 1 of qemuList
    tell qemuProcess
      set frontmost to true
      tell menu bar 1
        tell menu bar item "View"
          tell menu 1
            try
              click menu item "VGA"
            on error
              try
                click menu item "virtio"
              on error
                try
                  click menu item "VMWare SVGA"
                end try
              end try
            end try
          end tell
        end tell
      end tell
    end tell
  end if
end tell
'''

def refresh():
    try:
        subprocess.run(
            ["osascript", "-e", APPLESCRIPT],
            capture_output=True, timeout=3
        )
    except Exception:
        pass

def main():
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5
    print(f"wwRIG Display Refresher — polling QEMU View→VGA every {interval}s")
    print("Press Ctrl+C to stop.")
    try:
        while True:
            refresh()
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nStopped.")

if __name__ == "__main__":
    main()
